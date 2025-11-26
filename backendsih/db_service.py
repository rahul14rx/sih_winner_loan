from pymongo import MongoClient
from bson.objectid import ObjectId
import gridfs
import datetime
import os  # Added for local file saving

# --- CONFIGURATION ---
MONGO_URI = "mongodb://localhost:27017/"
DB_NAME = "sih_database"

client = MongoClient(MONGO_URI)
db = client[DB_NAME]
collection = db["sih"]
fs = gridfs.GridFS(db)

# Ensure a local directory exists to verify uploads visually
LOCAL_UPLOAD_DIR = "uploads"
if not os.path.exists(LOCAL_UPLOAD_DIR):
    os.makedirs(LOCAL_UPLOAD_DIR)

# --- AUTHENTICATION ---
def login_user(login_id, password, role):
    """
    Authenticates a user based on role.
    """
    if role == 'admin': # Bank Officer
        user = collection.find_one({"loan_officer_id": login_id})
        if user: 
            return {"status": "success", "name": "Bank Officer", "role": "admin", "officer_id": login_id}
        if login_id.startswith("OFF"):
             return {"status": "success", "name": "Bank Officer", "role": "admin", "officer_id": login_id}
    
    elif role == 'user': # Beneficiary
        user = collection.find_one({"user_id": login_id})
        if user:
            return {"status": "success", "user_id": login_id, "role": "user", "name": user.get("applicant_name", "Beneficiary")}
            
    return None

# --- OFFICER DASHBOARD ANALYTICS ---
def get_officer_stats(officer_id):
    pipeline = [
        {"$match": {"loan_officer_id": officer_id}},
        {"$group": {
            "_id": None,
            "total": {"$sum": 1},
            "verified": {"$sum": {"$cond": [{"$eq": ["$status", "verified"]}, 1, 0]}},
            "pending": {"$sum": {"$cond": [{"$eq": ["$status", "not verified"]}, 1, 0]}},
            "rejected": {"$sum": {"$cond": [{"$eq": ["$status", "rejected"]}, 1, 0]}}
        }}
    ]
    result = list(collection.aggregate(pipeline))
    if result:
        stats = result[0]
        del stats['_id']
        return stats
    return {"total": 0, "verified": 0, "pending": 0, "rejected": 0}

# --- LOAN MANAGEMENT ---
def get_loans_by_status(officer_id, status):
    query = {"loan_officer_id": officer_id}
    if status != 'all':
        if status == 'pending':
            query["status"] = "not verified"
        else:
            query["status"] = status
        
    cursor = collection.find(query)
    loans = []
    for doc in cursor:
        loans.append({
            "loan_id": doc.get("loan_id"),
            "applicant_name": doc.get("applicant_name", "Beneficiary"),
            "amount": doc.get("amount", 0.0),
            "loan_type": doc.get("loan_type", "General Loan"),
            "status": doc.get("status"),
            "date_applied": doc.get("date_applied", "N/A"),
            "user_id": doc.get("user_id")
        })
    return loans

def get_loan_details(loan_id):
    return collection.find_one({"loan_id": loan_id}, {"_id": 0})

def update_process_status(loan_id, process_id, status, officer_comment=""):
    collection.update_one(
        {"loan_id": loan_id, "process.id": process_id},
        {"$set": {
            "process.$.process_status": status,
            "process.$.officer_comment": officer_comment
        }}
    )
    
    doc = collection.find_one({"loan_id": loan_id})
    if doc and 'process' in doc:
        all_verified = all(p.get('process_status') == 'verified' for p in doc['process'])
        any_rejected = any(p.get('process_status') == 'rejected' for p in doc['process'])
        
        if all_verified:
            collection.update_one({"loan_id": loan_id}, {"$set": {"status": "verified"}})
        elif any_rejected:
            collection.update_one({"loan_id": loan_id}, {"$set": {"status": "rejected"}})
            
    return True

# --- BENEFICIARY MANAGEMENT ---
def create_beneficiary(data):
    default_processes = [
        {
            "id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View","data":None,
            "data_type": "image", "score": 0, "process_status": "not verified"
        },
        {
            "id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View","data":None,
            "data_type": "movement", "score": 0, "process_status": "not verified"
        },
        {
            "id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill","data":None,
            "data_type": "image", "score": 0, "process_status": "not verified"
        },
        {
            "id": "P4", "processid": 4, "what_to_do": "Record 360 Video","data":None,
            "data_type": "video", "score": 0, "process_status": "not verified"
        }
    ]

    today = datetime.date.today().strftime("%Y-%m-%d")

    new_doc = {
        "user_id": data['phone'],
        "loan_officer_id": data['officer_id'],
        "loan_id": data['loan_id'],
        "applicant_name": data['name'],
        "amount": float(data['amount']),
        "loan_type": data['loan_type'],
        "scheme": data['scheme'],
        "date_applied": today,
        "status": "not verified",
        "process": default_processes
    }

    try:
        if collection.find_one({"loan_id": data['loan_id']}):
            return False, "Loan ID already exists"
            
        collection.insert_one(new_doc)
        return True, "Beneficiary created successfully"
    except Exception as e:
        return False, str(e)

def mock_send_sms(phone, name, loan_id):
    print(f"\n[SMS GATEWAY SIMULATION] --------------------------------")
    print(f"To: {phone}")
    print(f"Message: Dear {name}, your loan application ({loan_id}) has been registered.")
    print(f"-----------------------------------------------------------\n")
    return True

# --- FILE HANDLING (UPDATED) ---
def update_process_media(user_id, loan_id, process_id, file_storage):
    """
    Stores the uploaded file (image/video) in GridFS
    and stores only file_id + metadata inside the loan.process[]
    """
    try:
        file_bytes = file_storage.read()

        # 1️⃣ Upload file to GridFS
        file_id = fs.put(file_bytes, filename=file_storage.filename)

        # 2️⃣ Generate unique local file copy (optional but useful)
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"{loan_id}{process_id}{timestamp}_{file_storage.filename}"
        file_path = os.path.join("uploads", filename)

        with open(file_path, "wb") as f:
            f.write(file_bytes)

        print(f"📁 Saved file at → {file_path}")
        print(f"🔗 GridFS file_id → {file_id}")

        # 3️⃣ Update MongoDB — store only reference instead of bytes
        result = collection.update_one(
            {"loan_id": loan_id, "user_id": user_id, "process.id": process_id},
            {
                "$set": {
                    "process.$.file_id": str(file_id),      # For retrieval/download
                    "process.$.file_path": file_path,       # For local preview
                    "process.$.data": None,                 # clear previous byte stores
                    "process.$.process_status": "pending_review"
                }
            }
        )

        return result.modified_count > 0

    except Exception as e:
        print("❌ Media upload failed:", e)
        return False



def get_file(file_id):
    try:
        return fs.get(ObjectId(file_id))
    except:
        return None

def get_user_process_data(user_id):
    cursor = collection.find({"user_id": user_id})
    results = []

    for doc in cursor:
        loan_data = {
            "userid": doc.get("user_id"),
            "loan_id": doc.get("loan_id"),
            "applicant_name": doc.get("applicant_name"), 
            "loan_type": doc.get("loan_type"),
            "process": []
        }

        for p in doc.get("process", []):
            loan_data["process"].append({
                "id": p.get("id"),
                "process_id": p.get("processid"),
                "what_to_do": p.get("what_to_do"),
                "data_type": p.get("data_type"),
                "status": p.get("process_status")
            })
        
        results.append(loan_data)

    return results
