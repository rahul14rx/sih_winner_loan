from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import io, os
from bson.objectid import ObjectId
import db_service
import AI_Engine as AI_Engine
from threading import Thread
DEBUG = True
app = Flask(__name__)
CORS(app)

fs = db_service.fs


def _base_url():
    return request.host_url.rstrip("/")


def _get_officer_id():
    return (request.args.get("officer_id") or request.headers.get("X-Officer-Id") or "OFF1001").strip()


def _process_to_api(p):
    pid = p.get("id") or ""
    process_id = p.get("processid") if p.get("processid") is not None else p.get("process_id")
    try:
        process_id = int(process_id)
    except Exception:
        process_id = 0

    status = p.get("process_status") or p.get("status") or "not verified"
    dt = p.get("data_type") or p.get("dataType") or "image"
    fid = p.get("file_id")

    out = {
        "id": str(pid),
        "process_id": process_id,
        "what_to_do": p.get("what_to_do") or "",
        "data_type": dt,
        "status": status,
        "file_id": fid,
        "uploaded_at": p.get("uploaded_at"),
        "filename": p.get("filename"),
        "utilization_amount": p.get("utilization_amount"),
        "is_required": bool(p.get("is_required", True)),
        "latitude": p.get("latitude"),
        "longitude": p.get("longitude"),
        "location_confidence": p.get("location_confidence"),
        "score": p.get("score"),
    }

    if fid:
        out["media_url"] = f"{_base_url()}/media/{fid}"
    else:
        out["media_url"] = None

    return out


def _loan_to_api(doc):
    if not doc:
        return None

    out = {
        "user_id": str(doc.get("user_id", "")),
        "loan_officer_id": str(doc.get("loan_officer_id", "")),
        "loan_id": str(doc.get("loan_id", "")),
        "applicant_name": doc.get("applicant_name") or "Beneficiary",
        "amount": float(doc.get("amount", 0.0) or 0.0),
        "loan_type": doc.get("loan_type") or "",
        "loan_category": doc.get("loan_category"),
        "loan_purpose": doc.get("loan_purpose"),
        "scheme": doc.get("scheme") or "",
        "date_applied": doc.get("date_applied") or "",
        "status": doc.get("status") or "not verified",
        "shop_floors": doc.get("shop_floors"),
        "stages": doc.get("stages"),
        "stage_utilization": doc.get("stage_utilization") or {},
        "process": [],
    }

    for p in (doc.get("process") or []):
        out["process"].append(_process_to_api(p))

    return out


@app.route("/health")
def health():
    ok, msg = db_service.ping_db()
    return jsonify({"ok": ok, "db": msg}), (200 if ok else 500)


@app.route("/login", methods=["POST"])
def login():
    print(1)
    data = request.get_json(silent=True) or request.form.to_dict()
    login_id = data.get("login_id") or data.get("mobile") or ""
    password = data.get("password") or ""
    role = data.get("role")

    if not role:
        return jsonify({"error": "Role required"}), 400

    if role == "user":
        user = db_service.login_user(login_id, password, role)
        if user:
            return jsonify(user), 200
        return jsonify({"error": "Invalid user"}), 401

    if role == "officer":
        officer = db_service.get_officer(login_id, password)
        if officer:
            return jsonify(officer), 200
        return jsonify({"error": "Invalid officer"}), 401

    return jsonify({"error": "Invalid Role"}), 400


@app.route("/user")
def get_user_data():
    user_id = request.args.get("id")
    if not user_id:
        return jsonify({"error": "id missing"}), 400

    docs = db_service.get_loans_for_user(user_id)
    out = []
    for d in docs:
        out.append(_loan_to_api(d))
    return jsonify({"data": out}), 200


@app.route("/loan_details", methods=["GET", "POST"])
def loan_page():
    data = request.get_json(silent=True) or {}
    loan_id = data.get("loan_id") if request.method == "POST" else request.args.get("loan_id")

    if not loan_id:
        return jsonify({"error": "loan_id missing"}), 400

    doc = db_service.get_loan_raw(loan_id)
    if not doc:
        return jsonify({"error": "not found"}), 404

    return jsonify({"loan_details": _loan_to_api(doc)}), 200


@app.route("/upload", methods=["POST","GET"])
def upload_file():
   
    try:
        # Explicitly get all data from the form
        
        process_id = request.form.get("process_id")
        loan_id = request.form.get("loan_id")
        file = request.files.get("file")
        utilization_amount = request.form.get("utilization_amount", "").strip()
        latitude = request.form.get("latitude")
        longitude = request.form.get("longitude")
        location_confidence = request.form.get("location_confidence")
        if not (loan_id and process_id and file):
            return jsonify({"error": "loan_id, process_id & file required"}), 400

        doc = db_service.get_loan_raw(loan_id)
        if not doc:
            return jsonify({"error": "Loan not found"}), 404

        user_id = doc.get("user_id")
       
        # Pass them as explicit arguments to the service
        ok = db_service.update_process_media(
            user_id=user_id,
            loan_id=loan_id,
            process_id=process_id,
            file_storage=file,
            utilization_amount=utilization_amount,
            latitude=latitude,
            longitude=longitude,
            location_confidence=location_confidence
        )

        if ok:
            Thread(target=AI_Engine.main, args=(loan_id, user_id, process_id)).start()
            return jsonify({"success": True}), 200

        return jsonify({"error": "Update failed"}), 400

    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/loan/stage_utilization", methods=["POST"])
def save_stage_util():
    data = request.get_json(silent=True) or request.form.to_dict()
    loan_id = (data.get("loan_id") or "").strip()
    user_id = (data.get("user_id") or "").strip()
    stage_no = data.get("stage_no")
    amount = data.get("amount")

    if not loan_id or stage_no is None or amount is None:
        return jsonify({"error": "loan_id, stage_no, amount required"}), 400

    ok, msg = db_service.set_stage_utilization(loan_id, user_id, stage_no, amount)
    return jsonify({"success": ok, "message": msg}), (200 if ok else 400)


@app.route("/bank/stats")
def off_stats():
    officer_id = _get_officer_id()
    return jsonify(db_service.get_officer_stats(officer_id)), 200


@app.route("/bank/loans")
def off_loans():
    officer_id = _get_officer_id()
    status = request.args.get("status", "all")
    return jsonify({"data": db_service.get_loans_by_status(officer_id, status)}), 200


@app.route("/bank/history")
def off_history():
    officer_id = _get_officer_id()
    status = request.args.get("status", "all")
    return jsonify({"data": db_service.get_history_by_status(officer_id, status)}), 200


@app.route("/bank/loan/<loan_id>")
def off_loan_detail(loan_id):
    d = db_service.get_loan_details(loan_id)
    if d:
        return jsonify(d), 200
    return jsonify({"error": "not found"}), 404


@app.route("/bank/verify", methods=["POST"])
def verify_process():
    d = request.get_json(silent=True) or {}
    ok = db_service.update_process_status(
        d.get("loan_id"),
        d.get("process_id"),
        d.get("status"),
        d.get("comment", "")
    )
    return jsonify({"success": ok}), (200 if ok else 400)


@app.route("/bank/beneficiary", methods=["POST"])
def create_new():
    data = request.form.to_dict()
    print(data)

    required = [
        "name", "phone", "amount", "loan_type", "scheme", "loan_id", "officer_id",
        "beneficiary_address", "asset_purchased"
    ]
    if not all(k in data and str(data[k]).strip() for k in required):
        missing = [k for k in required if k not in data or not str(data[k]).strip()]
        return jsonify({"error": "Missing required fields", "missing": missing}), 400

    creation_id = data.get("creation_id")
    if creation_id and db_service.beneficiary_exists_by_creation_id(creation_id):
        return jsonify({"error": "Duplicate beneficiary"}), 409

    loan_agreement_file = request.files.get("loan_agreement")
    if not loan_agreement_file:
        return jsonify({"error": "Missing 'loan_agreement' file"}), 400

    ok, msg = db_service.create_beneficiary(data, loan_agreement=loan_agreement_file)
    
    if ok:
        db_service.mock_send_sms(data["phone"], data["name"], data["loan_id"])
        return jsonify({"message": msg}), 201

    return jsonify({"error": msg}), 400



@app.route("/media/<file_id>")
def get_file(file_id):
    try:
        f = fs.get(ObjectId(file_id))
        name = (f.filename or "").lower()
        if name.endswith(".mp4") or name.endswith(".mov") or name.endswith(".mkv"):
            m = "video/mp4"
        else:
            m = "image/jpeg"
        return send_file(io.BytesIO(f.read()), mimetype=m, download_name=f.filename)
    except Exception:
        return jsonify({"error": "File not found"}), 404


@app.route("/")
def home():
    return jsonify({"message": "Nyay Sahayak Running"}), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 5000)), debug=DEBUG)
