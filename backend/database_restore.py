from pymongo import MongoClient

client = MongoClient("mongodb://localhost:27017/")
db = client["sih_database"]
collection = db["sih"]

# Clear old data (optional)
# collection.delete_many({})
print("⚠ Old data cleared\n")

# data = [
#     {
#         "user_id": "9876543210",
#         "loan_officer_id": "1111",
#         "loan_id": "Mithun",
#         "applicant_name": "Ravi Kumar",
#         "amount": 625400,
#         "loan_type": "Term Loan - Tractor",
#         "scheme": "NSFDC",
#         "date_applied": "2025-11-28",
#         "status": "not verified",
#         "process": [
#             {"id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View", "data": None, "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View", "data": None, "data_type": "movement", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill", "data": None, "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P4", "processid": 4, "what_to_do": "Record 360 Video", "data": None, "data_type": "video", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None}
#         ],
#         "loan_category": None,
#         "loan_purpose": None,
#         "loan_agreement_file_id": "6929d4267040d1608a0cee95",
#         "beneficiary_address": "12,Lakshmi Nagar ,ward No 4 Dharwad Karnataka - 580001",
#         "asset_purchased": "Mahindra 275 DITU",
#         "latitude": None,
#         "longitude": None
#     },
#     {
#         "user_id": "1111111111",
#         "loan_officer_id": "1111",
#         "loan_id": "111111111",
#         "applicant_name": "fyoctfygvh vft",
#         "amount": 1111111.0,
#         "loan_type": "Sanitation Equipment Loan - PPE kits (Safety gears)",
#         "scheme": "NSKFDC",
#         "date_applied": "2025-11-28",
#         "status": "not verified",
#         "process": [
#             {"id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View", "data": None, "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View", "data": None, "data_type": "movement", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill", "data": None, "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P4", "processid": 4, "what_to_do": "Record 360 Video", "data": None, "data_type": "video", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None}
#         ],
#         "loan_category": None,
#         "loan_purpose": None,
#         "loan_agreement_file_id": "6929d4cb7e8cb776ed067e9a",
#         "beneficiary_address": "1",
#         "asset_purchased": "1",
#         "latitude": None,
#         "longitude": None
#     },
#     {
#         "user_id": "9999999999",
#         "loan_officer_id": "1111",
#         "loan_id": "9999",
#         "applicant_name": "yuva",
#         "amount": 99999.0,
#         "loan_type": "Skill Development Loan - Laptop",
#         "scheme": "NSFDC",
#         "date_applied": "2025-11-28",
#         "status": "rejected",
#         "process": [
#             {"id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View", "data": None, "data_type": "image", "score": 0, "process_status": "rejected", "file_id": "6929e00b2a0d0b6cddaf653d", "latitude": None, "longitude": None, "filename": "sync_9999_P1.jpg", "updated_at": "2025-11-28T17:46:51.362857", "officer_comment": ""},
#             {"id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View", "data": None, "data_type": "movement", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None},
#             {"id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill", "data": None, "data_type": "image", "score": 0, "process_status": "pending_review", "file_id": "6929e00b2a0d0b6cddaf6541", "latitude": None, "longitude": None, "filename": "sync_9999_P3.jpg", "updated_at": "2025-11-28T17:46:51.458578"},
#             {"id": "P4", "processid": 4, "what_to_do": "Record 360 Video", "data": None, "data_type": "video", "score": 0, "process_status": "pending_review", "file_id": "6929e00b2a0d0b6cddaf6545", "latitude": None, "longitude": None, "filename": "sync_9999_P4.mp4", "updated_at": "2025-11-28T17:46:51.905394"}
#         ],
#         "loan_category": None,
#         "loan_purpose": None,
#         "loan_agreement_file_id": "6929d972344e7ea065786aff",
#         "beneficiary_address": "dawdad",
#         "asset_purchased": "dawda",
#         "latitude": None,
#         "longitude": None
#     },
#     {
#         "user_id": "8668038686",
#         "loan_officer_id": "1111",
#         "loan_id": "jk",
#         "applicant_name": "mithun",
#         "amount": 363.0,
#         "loan_type": "Sanitation Equipment Loan - PPE kits (Safety gears)",
#         "scheme": "NSKFDC",
#         "date_applied": "2025-11-28",
#         "status": "not verified",
#         "process": [
#             {"id": "P1", "processid": 1, "what_to_do": "Upload Asset Front View", "data": None, "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None, "is_required": True, "location_confidence": None},
#             {"id": "P2", "processid": 2, "what_to_do": "Upload Asset Side View", "data": None, "data_type": "movement", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None, "is_required": True, "location_confidence": None},
#             {"id": "P3", "processid": 3, "what_to_do": "Upload Invoice Bill", "data": None, "data_type": "image", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None, "is_required": True, "location_confidence": None},
#             {"id": "P4", "processid": 4, "what_to_do": "Record 360 Video", "data": None, "data_type": "video", "score": 0, "process_status": "not verified", "file_id": None, "latitude": None, "longitude": None, "is_required": True, "location_confidence": None}
#         ],
#         "loan_category": None,
#         "loan_purpose": None,
#         "loan_agreement_file_id": "6929e0322a0d0b6cddaf6564",
#         "beneficiary_address": "hdbs",
#         "asset_purchased": "gdvs",
#         "latitude": None,
#         "longitude": None
#     }
# ]

# collection.insert_many(data)
# print("🔥 Data inserted successfully!")
print("Current collection data:\n") 
for doc in collection.find(): 
    print(doc) 
    print("------------------------------------")