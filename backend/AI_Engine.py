
# ======================= DB CONNECTION ==========================
from pymongo import MongoClient, ASCENDING
from bson.objectid import ObjectId
import gridfs
import new_app as app
import numpy as np
import cv2
import rc_main

client = MongoClient("mongodb://localhost:27017/")
db = client["sih_database"]
collection = db["sih"]
fs = gridfs.GridFS(db)


# ======================= IMAGE READ UTILITY ======================
def _read_cv2_image(file_bytes: bytes):
    nparr = np.frombuffer(file_bytes, np.uint8)
    img = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
    return img


# ======================= FIXED RETRIEVE FUNCTION =================
def retrive(loan_id, user_id, process_id):
    loan = collection.find_one(
        {"loan_id": loan_id, "user_id": user_id},
        {"process": 1}
    )

    if not loan or "process" not in loan:
        print("❌ Loan/Process Missing")
        return None

    # 🔥 Correctly pick the right process where id == process_id
    selected = next((p for p in loan["process"] if p.get("id") == process_id), None)
    
    if not selected:
        print("❌ Process ID not found")
        return None

    file_id = selected.get("file_id")
    if not file_id:
        print("⚠ No file uploaded for this process yet")
        return None

    try:
        return fs.get(ObjectId(file_id)).read()
    except:
        print("❌ Invalid GridFS ObjectId format")
        return None


# ======================= SEMANTIC ANALYSIS =======================
def semantic_Analysis(loan_id, user_id, process_id):
    result = retrive(loan_id, user_id, process_id)
    if not result:
        return 0
    return 75


# ======================= CNN PREDICTION ==========================
def CNN(loan_id, user_id, process_id):
    loan = collection.find_one(
        {"loan_id": loan_id, "user_id": user_id}
    )
    item_name = loan.get("loan_type")
    print(item_name)
    _,req=item_name.split("-")
    item_to_be_verified=req.lower().strip()
    from ultralytics import YOLO
    from PIL import Image
    import torch
    from io import BytesIO

    img_bytes = retrive(loan_id, user_id, process_id)
    if img_bytes is None:
        print("❌ No DB Image")
        return None

    print("🔍 Loading CNN model...")
    model = YOLO("best.pt")
    core = model.model
    core.eval()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    core.to(device)

    try:
        img = Image.open(BytesIO(img_bytes)).convert("RGB")
    except:
        print("❌ Image decode failed")
        return None

    img_resized = img.resize((224, 224))
    arr = np.array(img_resized, dtype="float32") / 255.0
    t = torch.tensor(arr).permute(2, 0, 1).unsqueeze(0).to(device)

    with torch.no_grad():
        logits = core(t)[0]
        probs = torch.softmax(logits, dim=1)[0]
        top = int(torch.argmax(probs))

    prediction = model.names[top]
    confidence = round(float(probs[top]) * 100, 2)

    print(f"\n========= CNN RESULT =========")
    print(f" Prediction : {prediction}")
    print(f" Confidence : {confidence}%")
    print("================================\n")

    if prediction.lower().strip() == item_to_be_verified:
        return 100
    return 0


# ======================= INVOICE VERIFICATION ====================
def invoice(loan_id, user_id, process_id):

    loan = collection.find_one(
        {"loan_id": loan_id, "user_id": user_id, "process.id": process_id},
        {"_id": 0}
    )
    if not loan:
        print("❌ Loan not found")
        return 0

    agreement = {
        "name": loan.get("applicant_name"),
        "phone": loan.get("user_id"),
        "address": loan.get("beneficiary_address"),
        "amount": loan.get("amount"),
        "item": loan.get("brand_and_model"),
        
    }

    img_bytes = retrive(loan_id, user_id, process_id)
    if img_bytes is None:
        return 0

    response = app.verify("invoice", agreement, img_bytes)
    return response["comparison"]["final_score"]


# ======================= FEES RECEIPT ============================
def fee_reciept(loan_id, user_id, process_id):
    loan = collection.find_one({"loan_id": loan_id, "user_id": user_id}, {"_id": 0})
    if not loan: return 0

    agreement = {
        "name": loan.get("applicant_name"),
        "college": loan.get("institution_name"),
        "amount": loan.get("amount")
    }

    img_bytes = retrive(loan_id, user_id, process_id)
    if img_bytes is None: return 0

    response = app.verify("fees_receipt", agreement, img_bytes)
    return response["comparison"]["final_score"]


# ======================= MARKSHEET ===============================
def verify_marksheet(loan_id, user_id, process_id):

    loan = collection.find_one({"loan_id": loan_id, "user_id": user_id}, {"_id": 0})
    if not loan: return 0

    agreement = {
        "name": loan.get("applicant_name"),
        "college": loan.get("institution_name")
    }

    img_bytes = retrive(loan_id, user_id, process_id)
    if img_bytes is None: return 0

    response = app.verify("marksheet", agreement, img_bytes)
    return response["comparison"]["final_score"]


# ======================= STUDENT ID ==============================
def verify_student_id(loan_id, user_id, process_id):

    loan = collection.find_one({"loan_id": loan_id, "user_id": user_id}, {"_id": 0})
    if not loan: return 0

    agreement = {
        "name": loan.get("applicant_name"),
        "college": loan.get("institution_name")
    }

    img_bytes = retrive(loan_id, user_id, process_id)
    if img_bytes is None: return 0

    response = app.verify("student_id", agreement, img_bytes)
    return response["comparison"]["final_score"]

# ======================= RC VERIFICATION ===========================
def verify_rc(loan_id, user_id, process_id):
    # 1) Fetch loan
    loan = collection.find_one(
        {"loan_id": loan_id, "user_id": user_id},
        {"_id": 0}
    )
    if not loan:
        return 0

    # 2) Fetch RC image
    img_bytes = retrive(loan_id, user_id, process_id)
    if img_bytes is None:
        return 0

    # 3) Directly read fields from loan (as you said every field is present)
    name = loan.get("applicant_name", "")
    address = loan.get("beneficiary_address", "")
    phone = loan.get("user_id", "")
    vehicle_make = loan.get("brand_and_model", "")
    vehicle_model = loan.get("brand_and_model", "")
    vehicle_color = loan.get("vehicle_color", "")

    # 4) Call main verification logic (pure python)
    result = rc_main.verify_officer(
        image_bytes=img_bytes,
        name=name,
        address=address,
        phone=phone,
        vehicle_make=vehicle_make,
        vehicle_model=vehicle_model,
        vehicle_color=vehicle_color
    )

    # 5) Return final result
    if result["status"]:
        return 100
    return 0



# ======================= TEST ============================
#print(invoice(loan_id="Mithun", user_id="9876543210", process_id="P1"))
def main(loan_id, user_id, process_id):
    print("Starting AI Engine...")

    # find loan with full process list (we need the index)
    loan = collection.find_one(
        {"loan_id": loan_id, "user_id": user_id},
        {"process": 1}
    )
    if not loan or "process" not in loan:
        print("Loan or processes not found")
        return 0

    # find index of the desired process entry (match exact id)
    proc_list = loan["process"]
    idx = next((i for i, p in enumerate(proc_list) if str(p.get("id")) == str(process_id)), None)

    if idx is None:
        print(f"Process {process_id} not found in loan {loan_id}")
        return 0

    # compute total score by reading the processid list from that element
    selected = proc_list[idx]
    process_steps = selected.get("processid", [])
    total_score = 0
    for step in process_steps:
        if step == 1:
            total_score += CNN(loan_id, user_id, process_id)
        elif step == 2:
            total_score += invoice(loan_id, user_id, process_id)
        elif step == 3:
            total_score += verify_marksheet(loan_id, user_id, process_id)
        elif step == 4:
            total_score += fee_reciept(loan_id, user_id, process_id)
        elif step == 5:
            total_score += verify_student_id(loan_id, user_id, process_id)
        elif step == 6:
            total_score += verify_rc(loan_id, user_id, process_id)
        elif step == 7:
            total_score += semantic_Analysis(loan_id, user_id, process_id)
        # add other steps as needed

    # Now update the exact array element by index
    score_field = f"process.{idx}.score"

    res = collection.update_one(
        {"loan_id": loan_id, "user_id": user_id},
        {"$set": {score_field: total_score}}
    )

    if res.modified_count:
        print(f"Updated loan {loan_id} process[{idx}] with score {total_score}")
    else:
        print("Update did not modify any document (check filter)")

    return total_score


