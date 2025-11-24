from pymongo import MongoClient
from bson.objectid import ObjectId
import gridfs
import datetime

# --- CONFIGURATION ---
MONGO_URI = "mongodb://localhost:27017/"
DB_NAME = "sih_database"

client = MongoClient(MONGO_URI)
db = client[DB_NAME]
collection = db["sih"]
fs = gridfs.GridFS(db)

# ---------------------- AUTH ----------------------
def login_user(login_id, password=None, role=None):
    """
    Authenticates either Bank Officer or Beneficiary.
    """
    if role == "admin":
        user = collection.find_one({"loan_officer_id": login_id})
        if user:
            return {
                "status": "success",
                "name": user.get("applicant_name", "Bank Officer"),
                "role": "admin",
                "officer_id": login_id
            }
        return None

    elif role == "user":
        user = collection.find_one({"user_id": login_id})
        if user:
            return {
                "status": "success",
                "user_id": login_id,
                "role": "user",
                "name": user.get("applicant_name", "Beneficiary")
            }
        return None

    return None


# ---------------------- BENEFICIARY CREATION ----------------------
def create_beneficiary(data):
    default_steps = [
        {
            "id": "P1",
            "step_no": 1,
            "title": "Upload Asset Front View",
            "data_type": "image",
            "process_status": "not verified",
            "data": []
        },
        {
            "id": "P2",
            "step_no": 2,
            "title": "Upload Asset Side View",
            "data_type": "image",
            "process_status": "not verified",
            "data": []
        },
        {
            "id": "P3",
            "step_no": 3,
            "title": "Upload Invoice Bill",
            "data_type": "image",
            "process_status": "not verified",
            "data": []
        },
        {
            "id": "P4",
            "step_no": 4,
            "title": "Record 360 Video",
            "data_type": "video",
            "process_status": "not verified",
            "data": []
        }
    ]

    new_doc = {
        "user_id": data["phone"],
        "loan_officer_id": data["officer_id"],
        "loan_id": data["loan_id"],
        "applicant_name": data["name"],
        "amount": float(data["amount"]),
        "loan_type": data["loan_type"],
        "scheme": data["scheme"],
        "date_applied": datetime.date.today().isoformat(),
        "status": "not verified",
        "process": default_steps
    }

    collection.insert_one(new_doc)
    return True


# ---------------------- FETCH LOANS FOR BENEFICIARY ----------------------
def get_user_process_data(user_id):
    loans = list(collection.find({"user_id": user_id}))
    result = []

    for doc in loans:
        transformed = {
            "user_id": doc.get("user_id"),
            "loan_id": doc.get("loan_id"),
            "applicant_name": doc.get("applicant_name"),
            "loan_type": doc.get("loan_type"),
            "process": []
        }

        for p in doc.get("process", []):
            transformed["process"].append({
                "id": p.get("id"),
                "step_no": p.get("step_no"),
                "title": p.get("title"),
                "data_type": p.get("data_type"),
                "process_status": p.get("process_status"),
                "data": p.get("data", [])
            })

        result.append(transformed)

    return result


# ---------------------- UPDATE PROCESS MEDIA ----------------------
def update_process_media(user_id, loan_id, process_id, file_storage):
    """
    Uploads file to GridFS and attaches metadata to process step.
    RETURNS: file_id (IMPORTANT)
    """
    try:
        # Save file to GridFS
        file_id = fs.put(
            file_storage,
            filename=file_storage.filename,
            content_type=file_storage.content_type
        )

        # Append new data entry, not overwrite
        collection.update_one(
            {
                "user_id": user_id,
                "loan_id": loan_id,
                "process.id": process_id
            },
            {
                "$push": {
                    "process.$.data": {
                        "file_id": str(file_id),
                        "timestamp": datetime.datetime.utcnow()
                    }
                },
                "$set": {
                    "process.$.process_status": "pending_review"
                }
            }
        )

        return file_id

    except Exception as e:
        print("Error saving file:", e)
        return None


# ---------------------- GET FILE FROM GRIDFS ----------------------
def get_file_from_gridfs(file_id):
    try:
        return fs.get(ObjectId(file_id))
    except:
        return None
