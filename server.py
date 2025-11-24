# server.py  
from flask import Flask, request, jsonify, Response  
from flask_cors import CORS  
from werkzeug.utils import secure_filename  
import traceback  
import datetime

from db_service import (  
    login_user,  
    create_beneficiary,  
    get_user_process_data,  
    update_process_media,  
    get_file_from_gridfs  
)

app = Flask(__name__)  
CORS(app)  

@app.route("/")  
def home():  
    return "Loan Utilization Verification API Running", 200  

@app.route("/login", methods=["POST"])  
def login():  
    data = request.get_json()  
    phone = data.get("phone")  
    try:  
        user = login_user(phone)  
        if user:  
            return jsonify({"status": "success", "user": user}), 200  
        return jsonify({"status": "error", "message": "User not found"}), 404  
    except Exception as e:  
        traceback.print_exc()  
        return jsonify({"status": "error", "message": str(e)}), 500  

@app.route("/create_beneficiary", methods=["POST"])  
def create_beneficiary_route():  
    data = request.get_json()  
    try:  
        result = create_beneficiary(data)  
        return jsonify({"status": "success", "result": result}), 200  
    except Exception as e:  
        traceback.print_exc()  
        return jsonify({"status": "error", "message": str(e)}), 500  

@app.route("/user", methods=["GET"])  
def fetch_user_data():  
    phone = request.args.get("id")  
    try:  
        result = get_user_process_data(phone)  
        return jsonify({"status": "success", "loans": result}), 200  
    except Exception as e:  
        traceback.print_exc()  
        return jsonify({"status": "error", "message": str(e)}), 500  

@app.route("/upload", methods=["POST"])  
def upload():  
    try:  
        user_id = request.form.get("user_id")  
        loan_id = request.form.get("loan_id")  
        process_id = request.form.get("process_id")  
        if "file" not in request.files:  
            return jsonify({"status": "error", "message": "File missing"}), 400  

        file = request.files["file"]  
        filename = secure_filename(file.filename)  
        # Save file in GridFS and update metadata  
        file_id = update_process_media(  
            user_id=user_id,  
            loan_id=loan_id,  
            process_id=process_id,  
            file=file  
        )  
        return jsonify({  
            "status": "success",  
            "file_id": str(file_id)  
        }), 200  
    except Exception as e:  
        traceback.print_exc()  
        return jsonify({"status": "error", "message": str(e)}), 500  

@app.route("/file/<file_id>", methods=["GET"])  
def get_file(file_id):  
    try:  
        gridout = get_file_from_gridfs(file_id)  
        if gridout is None:  
            return jsonify({"error": "File not found"}), 404  
        mime = gridout.content_type or "application/octet-stream"  
        file_bytes = gridout.read()  
        return Response(file_bytes, mimetype=mime)  
    except Exception as e:  
        traceback.print_exc()  
        return jsonify({"error": "internal server error", "message": str(e)}), 500  

if __name__ == "__main__":  
    # Running on all interfaces so mobile devices can reach it  
    app.run(host="0.0.0.0", port=5001, debug=True)
