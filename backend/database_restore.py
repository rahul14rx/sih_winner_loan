from pymongo import MongoClient

# ---------------------------------------
# COMMON INSTRUCTIONS
# ---------------------------------------
# COMMON_INSTRUCTIONS = {
#     "image": [
#         "Ensure the document is clearly visible.",
#         "Avoid glare or reflections.",
#         "Capture the full document without cropping.",
#         "Keep your hand steady while taking the picture."
#     ],
#     "video": [
#         "Record in a well-lit environment.",
#         "Hold the document steady while recording.",
#         "Ensure all details on the document are visible.",
#         "Avoid shaking or sudden movement."
#     ],
#     "movement": [
#         "Move the document slowly left and right.",
#         "Ensure the camera stays focused on the document.",
#         "Keep the document fully inside the frame.",
#         "Avoid fast or jerky hand movements."
#     ]
# }

# ---------------------------------------
# 1. CONNECT TO MONGODB
# ---------------------------------------
client = MongoClient("mongodb://localhost:27017/")
db = client["sih_database"]
collection = db["sih"]

# ---------------------------------------
# 2. DELETE EXISTING DATA
# ---------------------------------------
# collection.delete_many({})

# ---------------------------------------
# 3. SAMPLE DATA WITH COMMON INSTRUCTIONS
# ---------------------------------------
# example_data = [
#     {
#         "user_id": "1111111111",
#         "loan_officer_id": "OFF1001",
#         "loan_id": "LN9001",
#         "process": [
#             {
#                 "id": "P1",
#                 "processid": 1,
#                 "what_to_do": "Upload Aadhaar front",
#                 "data_type": "video",
#                 "instruction": COMMON_INSTRUCTIONS["video"],
#                 "score": 91,
#                 "data": "aadhaar_front_1111.png",
#                 "process_status": "not verified"
#             },
#             {
#                 "id": "P2",
#                 "processid": 2,
#                 "what_to_do": "Upload Aadhaar back",
#                 "data_type": "image",
#                 "instruction": COMMON_INSTRUCTIONS["image"],
#                 "score": 85,
#                 "data": "aadhaar_back_1111.png",
#                 "process_status": "not verified"
#             }
#         ],
#         "status": "verified"
#     },
#     {
#         "user_id": "0000000000",
#         "loan_officer_id": "OFF2001",
#         "loan_id": "LN9002",
#         "process": [
#             {
#                 "id": "P1",
#                 "processid": 1,
#                 "what_to_do": "Upload PAN front",
#                 "data_type": "movement",
#                 "instruction": COMMON_INSTRUCTIONS["movement"],
#                 "score": 88,
#                 "data": "pan_front_0000.png",
#                 "process_status": "not verified"
#             },
#             {
#                 "id": "P2",
#                 "processid": 2,
#                 "what_to_do": "Upload PAN back",
#                 "data_type": "image",
#                 "instruction": COMMON_INSTRUCTIONS["image"],
#                 "score": 73,
#                 "data": "pan_back_0000.png",
#                 "process_status": "not verified"
#             }
#         ],
#         "status": "not verified"
#     }
# ]

# ---------------------------------------
# 4. INSERT DATA
# ---------------------------------------
# collection.insert_many(example_data)
# print("New sample data inserted.\n")

# ---------------------------------------
# 5. PRINT DATA
# ---------------------------------------
print("Current collection data:\n")
for doc in collection.find():
    print(doc)
    print("------------------------------------")