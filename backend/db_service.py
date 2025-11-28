from pymongo import MongoClient
from bson.objectid import ObjectId
import gridfs
import datetime
import os

MONGO_URI = os.environ.get("MONGO_URI", "mongodb://localhost:27017/")
DB_NAME = "sih_database"

client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=5000)
db = client[DB_NAME]

collection = db["sih"]
history_collection = db["sih_history"]
officer_collection = db["sih_bank"]

fs = gridfs.GridFS(db)


def ping_db():
    try:
        client.admin.command("ping")
        return True, "ok"
    except Exception as e:
        return False, str(e)


def get_officer(login_id, password):
    q = {"officer_id": str(login_id), "password": str(password)}
    officer = officer_collection.find_one(q, {"password": 0})
    if not officer:
        return None
    officer["_id"] = str(officer["_id"])
    return officer


def login_user(login_id, password, role):
    if role == "user":
        user = collection.find_one({"user_id": str(login_id)})
        if user:
            return {"status": "success", "user_id": str(login_id), "role": "user",
                    "name": user.get("applicant_name", "Beneficiary")}
    return None


def get_loans_for_user(user_id):
    return list(collection.find({"user_id": str(user_id)}, {"_id": 0}))


def get_loan_raw(loan_id):
    return collection.find_one({"loan_id": str(loan_id)}, {"_id": 0})


def get_officer_stats(officer_id):
    pipeline = [
        {"$match": {"loan_officer_id": str(officer_id)}},
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
        stats.pop("_id", None)
        return stats
    return {"total": 0, "verified": 0, "pending": 0, "rejected": 0}


def get_loans_by_status(officer_id, status):
    query = {"loan_officer_id": str(officer_id)}
    st = (status or "all").strip().lower()

    if st != "all":
        if st == "pending":
            query["status"] = "not verified"
        else:
            query["status"] = st

    loans = []
    for doc in collection.find(query, {"_id": 0}):
        loans.append({
            "loan_id": doc.get("loan_id"),
            "applicant_name": doc.get("applicant_name", "Beneficiary"),
            "amount": float(doc.get("amount", 0.0) or 0.0),
            "loan_type": doc.get("loan_type", "General Loan"),
            "loan_category": doc.get("loan_category"),
            "loan_purpose": doc.get("loan_purpose"),
            "scheme": doc.get("scheme"),
            "status": doc.get("status"),
            "date_applied": doc.get("date_applied", "N/A"),
            "user_id": doc.get("user_id"),
        })
    return loans


def get_loan_details(loan_id):
    return collection.find_one({"loan_id": str(loan_id)}, {"_id": 0})


def upsert_history_from_loan(loan_id):
    doc = collection.find_one({"loan_id": str(loan_id)}, {"_id": 0})
    if not doc:
        return False

    st = (doc.get("status") or "").strip().lower()
    if st not in ("verified", "rejected"):
        return False

    now = datetime.datetime.utcnow().isoformat()
    h = {
        "loan_id": doc.get("loan_id"),
        "loan_officer_id": doc.get("loan_officer_id"),
        "user_id": doc.get("user_id"),
        "applicant_name": doc.get("applicant_name"),
        "amount": float(doc.get("amount", 0.0) or 0.0),
        "loan_type": doc.get("loan_type"),
        "loan_category": doc.get("loan_category"),
        "loan_purpose": doc.get("loan_purpose"),
        "scheme": doc.get("scheme"),
        "status": st,
        "date_applied": doc.get("date_applied"),
        "closed_at": now,
        "updated_at": now,
    }

    history_collection.update_one(
        {"loan_id": str(loan_id)},
        {"$set": h, "$setOnInsert": {"created_at": now}},
        upsert=True
    )
    return True


def get_history_by_status(officer_id, status):
    q = {"loan_officer_id": str(officer_id)}
    st = (status or "all").strip().lower()
    if st != "all":
        q["status"] = st

    out = []
    for doc in history_collection.find(q, {"_id": 0}).sort("closed_at", -1):
        out.append({
            "loan_id": doc.get("loan_id"),
            "applicant_name": doc.get("applicant_name", "Beneficiary"),
            "amount": float(doc.get("amount", 0.0) or 0.0),
            "loan_type": doc.get("loan_type", "Loan"),
            "loan_category": doc.get("loan_category"),
            "loan_purpose": doc.get("loan_purpose"),
            "scheme": doc.get("scheme"),
            "status": doc.get("status"),
            "date_applied": doc.get("date_applied", "N/A"),
            "user_id": doc.get("user_id", ""),
        })
    return out


def update_process_status(loan_id, process_id, status, officer_comment=""):
    if not loan_id or process_id is None:
        return False

    status = (status or "").strip().lower()
    if status not in ("verified", "rejected", "not verified", "pending_review"):
        return False

    upd = {"$set": {
        "process.$.process_status": status,
        "process.$.officer_comment": officer_comment
    }}

    r = collection.update_one(
        {"loan_id": str(loan_id), "process.id": str(process_id)},
        upd
    )

    if r.matched_count == 0 and str(process_id).isdigit():
        r = collection.update_one(
            {"loan_id": str(loan_id), "process.processid": int(process_id)},
            upd
        )

    if r.matched_count == 0:
        return False

    doc = collection.find_one({"loan_id": str(loan_id)}, {"process": 1})
    if doc and "process" in doc:
        all_verified = all(p.get("process_status") == "verified" for p in doc["process"])
        any_rejected = any(p.get("process_status") == "rejected" for p in doc["process"])

        new_status = "not verified"
        if all_verified:
            new_status = "verified"
        elif any_rejected:
            new_status = "rejected"

        collection.update_one({"loan_id": str(loan_id)}, {"$set": {"status": new_status}})

        if new_status in ("verified", "rejected"):
            upsert_history_from_loan(loan_id)

    return True


def _is_construction(loan_type, scheme):
    t = (loan_type or "").lower()
    s = (scheme or "").lower()
    return ("construction" in t) or ("construction" in s) or ("shop" in t) or ("shop" in s)


def _build_default_processes(data):
    lt = (data.get("loan_type") or "").strip()
    sc = (data.get("scheme") or "").strip()

    if not _is_construction(lt, sc):
        return [
            {"id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "is_required": True},
            {"id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View", "data": None,
             "data_type": "movement", "score": 0, "process_status": "not verified", "file_id": None, "is_required": True},
            {"id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "is_required": True},
            {"id": "P4", "processid": 4, "what_to_do": "Record 360 Video", "data": None,
             "data_type": "video", "score": 0, "process_status": "not verified", "file_id": None, "is_required": True},
        ]

    stages = data.get("stages") or data.get("shop_floors") or data.get("floors") or "4"
    try:
        stages = int(str(stages))
    except Exception:
        stages = 4
    if stages <= 0:
        stages = 4

    template = [
        ("Front elevation view photo", "image"),
        ("Inner construction view photo", "image"),
        ("Invoice / Bill photo", "image"),
        ("360 degree video", "video"),
    ]

    out = []
    pid = 1
    for s in range(1, stages + 1):
        for title, dt in template:
            out.append({
                "id": f"P{pid}",
                "processid": pid,
                "what_to_do": f"Stage {s}: {title}",
                "data": None,
                "data_type": dt,
                "score": 0,
                "process_status": "not verified",
                "file_id": None,
                "is_required": True,
            })
            pid += 1
    return out


def create_beneficiary(data, loan_agreement=None):

    default_processes = [
        {"id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View",
         "data": None, "data_type": "image", "score": 0,
         "process_status": "not verified", "file_id": None,
         "latitude": None, "longitude": None},

        {"id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View",
         "data": None, "data_type": "movement", "score": 0,
         "process_status": "not verified", "file_id": None,
         "latitude": None, "longitude": None},

        {"id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill",
         "data": None, "data_type": "image", "score": 0,
         "process_status": "not verified", "file_id": None,
         "latitude": None, "longitude": None},

        {"id": "P4", "processid": 4, "what_to_do": "Record 360 Video",
         "data": None, "data_type": "video", "score": 0,
         "process_status": "not verified", "file_id": None,
         "latitude": None, "longitude": None},
    ]

    today = datetime.date.today().strftime("%Y-%m-%d")

    loan_agreement_file_id = None # Renamed for clarity
    if loan_agreement: # Changed here
        try:
            # Changed here
            loan_agreement_file_id = str(fs.put(loan_agreement.read(), filename=loan_agreement.filename))
        except Exception as e:
            print(f"Error saving file to GridFS: {e}")
            loan_agreement_file_id = None

    new_doc = {
        "user_id": data.get("phone"),
        "loan_officer_id": data.get("officer_id"),
        "loan_id": data.get("loan_id"),
        "applicant_name": data.get("name"),
        "amount": float(data.get("amount")),
        "loan_type": data.get("loan_type"),
        "scheme": data.get("scheme"),
        "date_applied": today,
        "status": "not verified",
        "process": default_processes,
        "loan_category": data.get("loan_category"),
        "loan_purpose": data.get("loan_purpose"),
        # Changed the key name to be consistent
        "loan_agreement_file_id": loan_agreement_file_id,
        "beneficiary_address": data.get("beneficiary_address"),
        "asset_purchased": data.get("asset_purchased"),
        "latitude": None,
        "longitude": None,
    }

    if collection.find_one({"loan_id": new_doc["loan_id"]}):
        return False, "Loan ID already exists"

    collection.insert_one(new_doc)
    return True, "Beneficiary created successfully"

def mock_send_sms(phone, name, loan_id):
    print(f"To: {phone}")
    print(f"Message: Dear {name}, your loan application ({loan_id}) has been registered.")
    return True


def update_process_media(user_id, loan_id, process_id, file_storage, utilization_amount=""):
    try:
        file_bytes = file_storage.read()
        gid = fs.put(file_bytes, filename=file_storage.filename)
        gid_str = str(gid)

        now = datetime.datetime.utcnow().isoformat()

        extra = {}
        if utilization_amount:
            try:
                extra["process.$.utilization_amount"] = float(utilization_amount)
            except Exception:
                extra["process.$.utilization_amount"] = utilization_amount

        q1 = {"loan_id": str(loan_id), "user_id": str(user_id), "process.id": str(process_id)}
        u = {
            "$set": {
                "process.$.file_id": gid_str,
                "process.$.filename": file_storage.filename,
                "process.$.uploaded_at": now,
                "process.$.data": None,
                "process.$.process_status": "pending_review",
                **extra
            }
        }

        r = collection.update_one(q1, u)

        if r.matched_count == 0 and str(process_id).isdigit():
            q2 = {"loan_id": str(loan_id), "user_id": str(user_id), "process.processid": int(process_id)}
            r = collection.update_one(q2, u)

        return r.modified_count > 0

    except Exception:
        return False


def set_stage_utilization(loan_id, user_id, stage_no, amount):
    try:
        sn = int(str(stage_no))
    except Exception:
        return False, "invalid stage_no"

    try:
        amt = float(str(amount))
    except Exception:
        return False, "invalid amount"

    q = {"loan_id": str(loan_id)}
    if user_id:
        q["user_id"] = str(user_id)

    r = collection.update_one(q, {"$set": {f"stage_utilization.{sn}": amt}})
    if r.matched_count == 0:
        return False, "loan not found"
    return True, "saved"


def get_file(file_id):
    try:
        return fs.get(ObjectId(file_id))
    except Exception:
        return None
