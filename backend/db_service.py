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
            return {
                "status": "success",
                "user_id": str(login_id),
                "role": "user",
                "name": user.get("applicant_name", "Beneficiary"),
            }
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
            "rejected": {"$sum": {"$cond": [{"$eq": ["$status", "rejected"]}, 1, 0]}},
        }},
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
        upsert=True,
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
        "process.$.officer_comment": officer_comment,
    }}

    r = collection.update_one(
        {"loan_id": str(loan_id), "process.id": str(process_id)},
        upd,
    )

    if r.matched_count == 0 and str(process_id).isdigit():
        r = collection.update_one(
            {"loan_id": str(loan_id), "process.processid": int(process_id)},
            upd,
        )

    if r.matched_count == 0:
        return False

    doc = collection.find_one({"loan_id": str(loan_id)}, {"process": 1})
    if doc and "process" in doc:
        # Flatten any nested process lists
        raw_procs = doc.get("process", [])
        procs = []
        for p in raw_procs:
            if isinstance(p, list):
                procs.extend([x for x in p if isinstance(x, dict)])
            elif isinstance(p, dict):
                procs.append(p)

        all_verified = bool(procs) and all(p.get("process_status") == "verified" for p in procs)
        any_rejected = any(p.get("process_status") == "rejected" for p in procs)

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
    item_type = lt.split("-")[-1]
    item_type = item_type.lower().strip()
    print(item_type, "item_type")

    if item_type in ["laptop", "sewing machines"]:
        print(1)
        return [
            {"id": "P1", "processid": [1], "what_to_do": "Upload Asset Front View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [1], "what_to_do": "Upload Asset Side View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P3", "processid": [2], "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P4", "processid": [0], "what_to_do": "Record 360 Video", "data": None,
             "data_type": "movement", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
        ]

    elif item_type in ["tractors", "auto rickshaws"]:
        print(2)
        return [
            {"id": "P1", "processid": [1], "what_to_do": "Upload Asset Front View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [2], "what_to_do": "Upload Asset Side View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P3", "processid": [3], "what_to_do": "Upload Number Plate", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P4", "processid": [4], "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P5", "processid": [5], "what_to_do": "Record 360 Video", "data": None,
             "data_type": "movement", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
        ]

    elif item_type in ["ppe kits (safety gears)"]:
        print(3)
        return [
            {"id": "P1", "processid": [1], "what_to_do": "Top ordered View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [2], "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
        ]

    elif item_type in ["cows"]:
        print(4)
        return [
            {"id": "P1", "processid": [1], "what_to_do": "Upload Ear Tag Close up View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [2], "what_to_do": "Upload Front View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P3", "processid": [3], "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P4", "processid": [4], "what_to_do": "Record 360 Video", "data": None,
                "data_type": "movement", "score": 0, "process_status": "not verified",
                "file_id": None, "is_required": True, "latitude": None, "longitude": None,
                "location_confidence": None
            }
        ]

    elif item_type in ["course"]:
        print(5)
        return [
            {"id": "P1", "processid": [1], "what_to_do": "Upload Course Certificate", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [2], "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
        ]

    elif item_type in ["education loan","admission fees","hostel fees"]:
        print(6)
        base = [
            {"id": "P1", "processid": [1], "what_to_do": "Upload Marksheet", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [2], "what_to_do": "Upload Fee Receipt", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
        ]
        total_course_year = int(data.get("total_course_year", 0) or 0)
        if total_course_year <= 0:
            return base
        return base * total_course_year

    elif item_type in ["shop construction / purchase"]:
        base = [
            {"id": "P1", "processid": [1], "what_to_do": "Upload Front Elevation View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P2", "processid": [2], "what_to_do": "Upload Inner Construction View", "data": None,
             "data_type": "image", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P3", "processid": [3], "what_to_do": "Upload Invoice Bill", "data": None,
             "data_type": "scanner", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
            {"id": "P4", "processid": [4], "what_to_do": "Record 360 Video", "data": None,
             "data_type": "movement", "score": 0, "process_status": "not verified",
             "file_id": None, "is_required": True, "latitude": None, "longitude": None,
             "location_confidence": None},
        ]
        total_floors = int(data.get("floors", 0) or 0)
        if total_floors <= 0:
            return base
        return base * total_floors

    return []


def create_beneficiary(data, loan_agreement=None):

    processes = _build_default_processes(data)

    today = datetime.date.today().strftime("%Y-%m-%d")

    loan_agreement_file_id = None
    if loan_agreement:
        try:
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
        "process": processes,
        "loan_category": data.get("loan_category"),
        "loan_purpose": data.get("loan_purpose"),
        "loan_agreement_file_id": loan_agreement_file_id,
        "beneficiary_address": data.get("beneficiary_address", None),
        "asset_purchased": data.get("asset_purchased", None),
        "institution_name": data.get("institution_name", None),
        "brand_and_model": data.get("brand_model", None),
        "no_of_cows": data.get("no of cows", None),
        "course_name": data.get("course_name", None),
        "course_provider_name": data.get("course_provider_name", None),
        "course_mode": data.get("course_mode", None),
        "total_course_year": data.get("total_course_year", 0),
        "latitude": None,
        "longitude": None,
        "total_floors": data.get("floors", 0),
        "is_required": True,
    }

    if collection.find_one({"loan_id": new_doc["loan_id"]}):
        return False, "Loan ID already exists"

    collection.insert_one(new_doc)
    print(new_doc)
    return True, "Beneficiary created successfully"
def mock_send_sms(phone, name, loan_id):
    print(f"To: {phone}")
    print(f"Message: Dear {name}, your loan application ({loan_id}) has been registered.")
    return True


def update_process_media(user_id, loan_id, process_id, file_storage,
                         utilization_amount=None, latitude=None, longitude=None,
                         location_confidence=None):
    try:
        file_bytes = file_storage.read()
        gid = fs.put(file_bytes, filename=file_storage.filename)
        gid_str = str(gid)

        now = datetime.datetime.utcnow().isoformat()

        set_payload = {
            "process.$.file_id": gid_str,
            "process.$.filename": file_storage.filename,
            "process.$.process_status": "pending_review",
            "process.$.updated_at": now,
        }

        if utilization_amount:
            try:
                set_payload["process.$.utilization_amount"] = float(utilization_amount)
            except (ValueError, TypeError):
                set_payload["process.$.utilization_amount"] = utilization_amount

        if latitude is not None and longitude is not None:
            try:
                set_payload["process.$.latitude"] = float(latitude)
                set_payload["process.$.longitude"] = float(longitude)
                if location_confidence is not None:
                    set_payload["process.$.location_confidence"] = float(location_confidence)
            except (ValueError, TypeError):
                print(f"Warning: Could not convert geo data to float for loan {loan_id}. Saving as string.")
                set_payload["process.$.latitude"] = latitude
                set_payload["process.$.longitude"] = longitude
                if location_confidence is not None:
                    set_payload["process.$.location_confidence"] = location_confidence

        q1 = {"loan_id": str(loan_id), "user_id": str(user_id), "process.id": str(process_id)}
        u = {"$set": set_payload}

        result = collection.update_one(q1, u)

        if result.matched_count == 0 and str(process_id).isdigit():
            q2 = {"loan_id": str(loan_id), "user_id": str(user_id), "process.processid": int(process_id)}
            result = collection.update_one(q2, u)

        return result.matched_count > 0

    except Exception as e:
        print(f"Error in update_process_media: {e}")
        return False
