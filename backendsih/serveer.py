# app.py
from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import io, os
from pymongo import MongoClient
from bson.objectid import ObjectId
import db_service1 as db_service # <-- you already have this

DEBUG = True
app = Flask(__name__)
CORS(app)

# ======================================================
# MONGO + GRIDFS CONNECT
# ======================================================
MONGO_URI = os.environ.get("MONGO_URI","mongodb://localhost:27017/")
client = MongoClient(MONGO_URI)
db = client["sih_database"]
officer_collection = db["sih_bank"]
fs = db_service.fs   # <-- MUST EXIST in db_service (GridFS instance)

if not os.path.exists("uploads"):
    os.makedirs("uploads")


# ======================================================
# LOGIN
# ======================================================
@app.route("/login", methods=["POST"])
def login():
    data = request.get_json(silent=True) or request.form.to_dict()
    login_id = data.get("login_id") or data.get("mobile")
    password = data.get("password")
    role = data.get("role")

    if not role:
        return jsonify({"error": "Role required"}), 400

    # ---- USER ----
    if role == "user":
        user = db_service.login_user(login_id, password, role)
        return jsonify(user), 200 if user else ({"error":"Invalid user"},401)

    # ---- OFFICER ----
    if role == "officer":
        q = {"officer_id": str(login_id), "password": str(password)}
        officer = officer_collection.find_one(q)
        if officer:
            officer["_id"]=str(officer["_id"]); officer.pop("password",None)
            return jsonify(officer),200
        return jsonify({"error":"Invalid officer"}),401
    
    return jsonify({"error":"Invalid Role"}),400


# ======================================================
# USER → GET PROCESS LIST
# ======================================================
@app.route("/user")
def get_user_data():
    user_id=request.args.get("id")
    if not user_id: return {"error":"id missing"},400
    return jsonify({"data": db_service.get_user_process_data(user_id)}),200


# ======================================================
# USER → UPLOAD MEDIA  (GRIDFS STORAGE)
# ======================================================
@app.route("/upload",methods=["POST"])
def upload_file():
    try:
        process_id=request.form.get("process_id")
        loan_id=request.form.get("loan_id")
        file=request.files.get("file")

        if not (loan_id and process_id and file):
            return {"error":"loan_id, process_id & file required"},400

        loan=db_service.get_loan_details(loan_id)
        if not loan: return {"error":"Loan not found"},404

        user_id=loan["user_id"]
        updated=db_service.update_process_media(user_id,loan_id,process_id,file)

        return ({"success":True},200) if updated else ({"error":"Update failed"},400)
    except Exception as e:
        return {"error":str(e)},500


# ======================================================
# OFFICER DASHBOARD
# ======================================================
@app.route("/bank/stats")
def off_stats():
    return jsonify(db_service.get_officer_stats("OFF1001"))

@app.route("/bank/loans")
def off_loans():
    return jsonify({"data": db_service.get_loans_by_status("OFF1001", request.args.get("status","all"))})

@app.route("/bank/loan/<loan_id>")
def off_loan_detail(loan_id):
    d=db_service.get_loan_details(loan_id)
    return (jsonify(d),200) if d else ({"error":"not found"},404)

@app.route("/bank/verify",methods=["POST"])
def verify_process():
    d=request.json
    ok=db_service.update_process_status(d["loan_id"],d["process_id"],d["status"],d.get("comment",""))
    return jsonify({"success":ok})


# ======================================================
# BANK ADMIN — ADD BENEFICIARY
# ======================================================
@app.route("/bank/beneficiary",methods=["POST"])
def create_new():
    data=request.form.to_dict()
    file=request.files.get("loan_document")

    if file:
        p=f"uploads/{data['loan_id']}_{file.filename}"
        file.save(p)
        data["loan_document_path"]=p

    ok,msg=db_service.create_beneficiary(data)
    return ({"message":msg},201) if ok else ({"error":msg},400)


# ======================================================
# STREAM MEDIA FROM GRIDFS
# ======================================================
@app.route("/media/<file_id>")
def get_file(file_id):
    try:
        f=fs.get(ObjectId(file_id))
        m="video/mp4" if f.filename.endswith(".mp4") else "image/jpeg"
        return send_file(io.BytesIO(f.read()), mimetype=m, download_name=f.filename)
    except:
        return {"error":"File not found"},404


# ======================================================
# 🟢 FIXED: RETURN CLEAN LOAN DETAILS *NO BYTES*
# ======================================================
@app.route("/loan_details",methods=["GET","POST"])
def loan_page():

    loan_id = request.json.get("loan_id") if request.method=="POST" else request.args.get("loan_id")
    if not loan_id: return {"error":"loan_id missing"},400

    doc=db["sih"].find_one({"loan_id":loan_id})
    if not doc: return {"error":"not found"},404

    doc["_id"]=str(doc["_id"])

    for p in doc.get("process",[]):
        # return only file reference (not bytes)
        p.pop("data",None)  
        p["media_url"] = f"http://127.0.0.1:5000/media/{p.get('file_id')}"

    return jsonify({"loan_details":doc}),200


@app.route("/")
def home():
    return {"message":"Nyay Sahayak Running"},200


if __name__=="__main__":
    app.run(host="0.0.0.0",port=5000,debug=DEBUG)
