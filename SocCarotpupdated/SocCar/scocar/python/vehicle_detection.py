# ─────────────────────────────────────────────────────────────────────────────
# AREA 1 (FastAPI) + AREA 7 (Python/OpenCV RTSP Handler)
#
# File: backend/vehicle_detection.py
#
# pip install fastapi uvicorn python-multipart firebase-admin ultralytics easyocr opencv-python
# ─────────────────────────────────────────────────────────────────────────────

from __future__ import annotations

import asyncio
import logging
import time
import uuid
from datetime import datetime
from typing import Optional

import cv2
import easyocr
import firebase_admin
import numpy as np
from fastapi import BackgroundTasks, FastAPI, HTTPException, UploadFile, File
from firebase_admin import credentials, firestore
from pydantic import BaseModel
from ultralytics import YOLO

logger = logging.getLogger("soccar")

# ── Firebase init ─────────────────────────────────────────────────────────────
if not firebase_admin._apps:
    cred = credentials.Certificate("serviceAccountKey.json")
    firebase_admin.initialize_app(cred)

db = firestore.client()

# ── Models ────────────────────────────────────────────────────────────────────
yolo_model = YOLO("yolov8n.pt")          # swap to custom-trained weights for plates
ocr_reader = easyocr.Reader(["en"], gpu=False)

app = FastAPI(title="SocCar AI Backend", version="2.0.0")


# ─────────────────────────────────────────────────────────────────────────────
# AREA 1: /detect-vehicle endpoint with discrepancy handling
# ─────────────────────────────────────────────────────────────────────────────

class DetectVehicleResponse(BaseModel):
    status: str          # "match" | "discrepancy" | "unknown_plate" | "not_registered"
    plateNumber: str
    registeredModel: Optional[str] = None
    detectedModel: Optional[str] = None
    vehicleLogId: str    # Firestore vehicleLogs doc ID created by this call
    message: str


def _read_plate_from_image(image_bytes: bytes) -> tuple[str, str]:
    """
    Returns (plate_number, detected_car_model) using YOLO + EasyOCR.
    In production, replace mock logic with your trained YOLO weights.
    """
    nparr = np.frombuffer(image_bytes, np.uint8)
    frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

    # ── YOLO detection ──────────────────────────────────────────────────────
    results = yolo_model(frame, verbose=False)

    detected_plate = ""
    detected_model = "Unknown"

    for box in results[0].boxes:
        cls_name: str = yolo_model.names[int(box.cls[0])]

        # Car model detection (class name from YOLO, e.g. "car", "truck", "motorcycle")
        if cls_name in ("car", "truck", "motorcycle", "bus"):
            detected_model = cls_name.title()

        # Plate crop (if your model has a "license_plate" class)
        if cls_name == "license_plate":
            x1, y1, x2, y2 = map(int, box.xyxy[0])
            plate_crop = frame[y1:y2, x1:x2]
            ocr_results = ocr_reader.readtext(plate_crop, detail=0)
            if ocr_results:
                detected_plate = "".join(ocr_results).upper().replace(" ", "")

    # Fallback: run OCR on the whole frame if no plate class found
    if not detected_plate:
        ocr_results = ocr_reader.readtext(frame, detail=0)
        detected_plate = "".join(ocr_results).upper().replace(" ", "")[:12]

    return detected_plate, detected_model


@app.post("/detect-vehicle", response_model=DetectVehicleResponse)
async def detect_vehicle(
    file: UploadFile = File(...),
    guard_id: str = "GUARD",
    gate_no: int = 1,
    camera_id: Optional[str] = None,
):
    """
    Upload a vehicle image. The endpoint:
      1. Extracts plate number and car model via YOLO + EasyOCR.
      2. Looks up the plate in Firestore `vehicles`.
      3. If found, compares the detected model with the registered model.
      4. Returns status: 'match' | 'discrepancy' | 'unknown_plate' | 'not_registered'
      5. Writes a vehicleLog document regardless (audit trail).
    """
    image_bytes = await file.read()
    plate_number, detected_model = _read_plate_from_image(image_bytes)

    registered_model: Optional[str] = None
    status: str = "unknown_plate"
    message: str = ""

    if plate_number:
        # ── Firestore lookup ───────────────────────────────────────────────
        vehicles_ref = db.collection("vehicles")
        query = vehicles_ref.where("plateNumber", "==", plate_number).limit(1).stream()
        vehicle_doc = next(query, None)

        if vehicle_doc:
            vehicle_data = vehicle_doc.to_dict()
            registered_model = vehicle_data.get("model", "")

            # ── AREA 1 FIX: explicit discrepancy check ─────────────────────
            if registered_model and detected_model != "Unknown":
                if registered_model.lower().strip() == detected_model.lower().strip():
                    status = "match"
                    message = f"Plate {plate_number} verified. Model matches: {registered_model}."
                else:
                    status = "discrepancy"
                    message = (
                        f"Plate {plate_number} registered but model mismatch: "
                        f"expected '{registered_model}', detected '{detected_model}'."
                    )
            else:
                # Model field missing or YOLO couldn't classify — treat as match
                # (guard can still visually verify)
                status = "match"
                message = f"Plate {plate_number} found. Model could not be compared."
        else:
            status = "not_registered"
            message = f"Plate {plate_number} detected but NOT in database."

    # ── Write vehicle log (always) ─────────────────────────────────────────
    log_ref = db.collection("vehicleLogs").document()
    log_ref.set(
        {
            "plateNumber": plate_number or "UNREADABLE",
            "detectedModel": detected_model,
            "registeredModel": registered_model,
            "status": status,
            "guardId": guard_id,
            "gateNo": gate_no,
            "cameraId": camera_id,          # AREA 7: which camera captured this
            "manual_override": False,
            "timestamp": firestore.SERVER_TIMESTAMP,
        }
    )

    return DetectVehicleResponse(
        status=status,
        plateNumber=plate_number or "",
        registeredModel=registered_model,
        detectedModel=detected_model,
        vehicleLogId=log_ref.id,
        message=message,
    )


# ─────────────────────────────────────────────────────────────────────────────
# AREA 7: RTSP Camera Stream — dynamic Firestore-backed feed handler
# ─────────────────────────────────────────────────────────────────────────────

class RTSPStreamProcessor:
    """
    Pulls RTSP/HTTP camera feeds stored in Firestore `cameras` collection
    and pipes frames into the YOLO/EasyOCR pipeline.

    Usage:
        processor = RTSPStreamProcessor(camera_id="abc123", gate_no=1)
        await processor.start()   # runs in a background asyncio task
        processor.stop()
    """

    def __init__(self, camera_id: str, gate_no: int, guard_id: str = "SYSTEM"):
        self.camera_id = camera_id
        self.gate_no = gate_no
        self.guard_id = guard_id
        self._running = False
        self._cap: Optional[cv2.VideoCapture] = None

    def _get_rtsp_url(self) -> Optional[str]:
        """Fetch the latest RTSP URL from Firestore (allows hot-reload)."""
        doc = db.collection("cameras").document(self.camera_id).get()
        if not doc.exists:
            logger.error(f"Camera {self.camera_id} not found in Firestore.")
            return None
        data = doc.to_dict()
        if data.get("status") != "active":
            logger.warning(f"Camera {self.camera_id} is not active.")
            return None
        return data.get("ipAddress")

    def _test_connection(self, url: str) -> bool:
        """Open the stream briefly to verify it's reachable."""
        cap = cv2.VideoCapture(url)
        ok = cap.isOpened()
        cap.release()
        return ok

    async def start(self):
        """
        Main loop: read frames from the RTSP stream, run detection every N frames.
        Runs as an asyncio task so it doesn't block the FastAPI event loop.
        """
        self._running = True
        frame_interval = 30   # process every 30th frame (~1fps @ 30fps source)
        frame_count = 0

        while self._running:
            # Re-fetch URL from Firestore (supports runtime IP changes)
            url = await asyncio.get_event_loop().run_in_executor(
                None, self._get_rtsp_url
            )

            if not url:
                await asyncio.sleep(10)
                continue

            # ── Open / reopen stream ─────────────────────────────────────
            if self._cap is None or not self._cap.isOpened():
                logger.info(f"Connecting to camera {self.camera_id}: {url}")
                self._cap = cv2.VideoCapture(url)
                if not self._cap.isOpened():
                    logger.error(f"Cannot open stream: {url}. Retrying in 10s…")
                    await asyncio.sleep(10)
                    continue

            # ── Read one frame ───────────────────────────────────────────
            ret, frame = await asyncio.get_event_loop().run_in_executor(
                None, self._cap.read
            )

            if not ret:
                logger.warning(f"Camera {self.camera_id} frame read failed. Reconnecting…")
                self._cap.release()
                self._cap = None
                await asyncio.sleep(2)
                continue

            frame_count += 1
            if frame_count % frame_interval != 0:
                await asyncio.sleep(0.01)
                continue

            # ── Encode frame and run detection ───────────────────────────
            _, buf = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, 80])
            image_bytes = buf.tobytes()

            plate, model = await asyncio.get_event_loop().run_in_executor(
                None, _read_plate_from_image, image_bytes
            )

            if plate:
                logger.info(
                    f"[Cam {self.camera_id}] Detected plate: {plate}, model: {model}"
                )
                await asyncio.get_event_loop().run_in_executor(
                    None,
                    self._write_detection_log,
                    plate,
                    model,
                )

            await asyncio.sleep(0.01)

    def _write_detection_log(self, plate: str, detected_model: str):
        """Writes a detection event to Firestore — includes cameraId per Area 7 spec."""
        log_ref = db.collection("vehicleLogs").document()
        log_ref.set(
            {
                "plateNumber": plate,
                "detectedModel": detected_model,
                "status": "auto_detected",
                "guardId": self.guard_id,
                "gateNo": self.gate_no,
                "cameraId": self.camera_id,     # AREA 7: camera provenance
                "manual_override": False,
                "timestamp": firestore.SERVER_TIMESTAMP,
            }
        )

    def stop(self):
        self._running = False
        if self._cap:
            self._cap.release()
            self._cap = None
        logger.info(f"Stream processor for camera {self.camera_id} stopped.")


# ── FastAPI endpoints for camera management ──────────────────────────────────

class TestStreamResponse(BaseModel):
    camera_id: str
    reachable: bool
    message: str


@app.get("/cameras/{camera_id}/test", response_model=TestStreamResponse)
async def test_camera_stream(camera_id: str):
    """Test whether the RTSP stream for a registered camera is reachable."""
    doc = db.collection("cameras").document(camera_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Camera not found")

    url: str = doc.to_dict().get("ipAddress", "")
    if not url:
        return TestStreamResponse(
            camera_id=camera_id, reachable=False, message="No IP address configured."
        )

    cap = cv2.VideoCapture(url)
    reachable = cap.isOpened()
    cap.release()

    return TestStreamResponse(
        camera_id=camera_id,
        reachable=reachable,
        message="Stream is reachable." if reachable else f"Cannot open stream: {url}",
    )


# ── Global registry of active stream processors ──────────────────────────────
_active_processors: dict[str, RTSPStreamProcessor] = {}


@app.post("/cameras/{camera_id}/start-stream")
async def start_camera_stream(
    camera_id: str, background_tasks: BackgroundTasks, guard_id: str = "SYSTEM"
):
    """Start processing RTSP stream for a camera in the background."""
    if camera_id in _active_processors:
        return {"message": f"Stream for {camera_id} already running."}

    doc = db.collection("cameras").document(camera_id).get()
    if not doc.exists:
        raise HTTPException(status_code=404, detail="Camera not found")

    gate_no: int = doc.to_dict().get("gateNo", 1)
    processor = RTSPStreamProcessor(camera_id=camera_id, gate_no=gate_no, guard_id=guard_id)
    _active_processors[camera_id] = processor
    background_tasks.add_task(processor.start)
    return {"message": f"Stream started for camera {camera_id}."}


@app.post("/cameras/{camera_id}/stop-stream")
async def stop_camera_stream(camera_id: str):
    """Stop a running RTSP stream processor."""
    processor = _active_processors.pop(camera_id, None)
    if not processor:
        raise HTTPException(status_code=404, detail="No active stream for this camera.")
    processor.stop()
    return {"message": f"Stream stopped for camera {camera_id}."}
