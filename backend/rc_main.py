import os
from typing import Dict, Any
from io import BytesIO

from mock_db import MOCK_DB
from ocr_plate import ocr_plate_bytes
from normalize import find_best_rc
from compare_rc import compare_officer_vs_api


def ping():
    return "ok"


# -------------------------------------------
# Helper class (still optional)
# -------------------------------------------
class MemoryUploadFile:
    """
    Simple class mimicking UploadFile but synchronous.
    Only used if you need a .read() wrapper.
    """
    def __init__(self, data: bytes, filename="image.jpg"):
        self.filename = filename
        self.file = BytesIO(data)

    def read(self):
        self.file.seek(0)
        return self.file.read()


# -------------------------------------------
# 1) Direct RC lookup
# -------------------------------------------
def rc_verify(payload: Dict[str, Any]):
    v = find_best_rc(str(payload.get("vehicle_no", "")), prefer=set(MOCK_DB.keys()))
    if not v:
        return {
            "status": False,
            "error_code": "INVALID_VEHICLE_NO",
            "message": "Invalid vehicle no",
            "vehicle_no": v
        }
    d = MOCK_DB.get(v)
    if not d:
        return {
            "status": False,
            "error_code": "NOT_FOUND",
            "message": "Vehicle not found",
            "vehicle_no": v
        }
    return {"status": True, "source": "MOCK", "vehicle_no": v, "vehicle": d}


# -------------------------------------------
# 2) Plate photo -> OCR -> vehicle details
# -------------------------------------------
def plate_verify(image_bytes: bytes):
    out = ocr_plate_bytes(image_bytes)
    v = out["vehicle_no"]

    if not v:
        return {
            "status": False,
            "error_code": "OCR_FAILED",
            "message": "Could not extract valid vehicle number",
            "extracted": out
        }

    d = MOCK_DB.get(v)
    if not d:
        return {
            "status": False,
            "error_code": "NOT_FOUND",
            "message": "Vehicle not found in mock DB",
            "vehicle_no": v,
            "extracted": out
        }

    return {
        "status": True,
        "source": "MOCK_OCR",
        "vehicle_no": v,
        "extracted": out,
        "vehicle": d
    }


# -------------------------------------------
# 3) Officer enters details + uploads plate photo
# -------------------------------------------
def verify_officer(
    image_bytes: bytes,

    name: str = "",
    address: str = "",
    phone: str = "",

    vehicle_make: str = "",
    vehicle_model: str = "",
    vehicle_color: str = "",
):
    plate = ocr_plate_bytes(image_bytes)
    plate_rc = plate["vehicle_no"]

    if not plate_rc:
        return {
            "status": False,
            "error_code": "PLATE_OCR_FAILED",
            "message": "Could not extract valid vehicle number",
            "plate": plate
        }

    vehicle = MOCK_DB.get(plate_rc)
    if not vehicle:
        return {
            "status": False,
            "error_code": "NOT_FOUND",
            "message": "Vehicle extracted but not found in mock DB",
            "vehicle_no": plate_rc,
            "plate": plate
        }

    officer_input = {
        "name": name,
        "address": address,
        "phone": phone,
        "vehicle_make": vehicle_make,
        "vehicle_model": vehicle_model,
        "vehicle_color": vehicle_color,
    }

    decision = compare_officer_vs_api(officer_input, vehicle)

    return {
        "status": True,
        "vehicle_no": plate_rc,
        "plate": plate,
        "officer_input": officer_input,
        "vehicle": vehicle,
        "decision": decision,
    }
