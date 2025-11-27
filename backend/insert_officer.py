# insert_officers.py
from pymongo import MongoClient

client = MongoClient("mongodb://localhost:27017/")
db = client["sih_database"]
officer_collection = db["sih_bank"]

# Clear old data (be careful in production!)
officer_collection.delete_many({})
print("Old data deleted.")

# Plain text sample (quick test) - NOTE: in production use hashed passwords
sample_officers = [
    {"officer_id": "1111", "password": "123"},
    {"officer_id": "1112", "password": "123"}
]

officer_collection.insert_many(sample_officers)
print("Inserted sample officers.")

for doc in officer_collection.find():
    print({"_id": str(doc["_id"]), "officer_id": doc.get("officer_id")})