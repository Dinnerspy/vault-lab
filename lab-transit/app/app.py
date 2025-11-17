import base64
import json
import os
import uuid
from datetime import datetime, timezone
from pathlib import Path

import hvac
from flask import Flask, flash, render_template, request

VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://vault:8200")
ROLE_ID_PATH = Path(os.environ.get("ROLE_ID_PATH", "/vault-approle/role_id"))
SECRET_ID_PATH = Path(os.environ.get("SECRET_ID_PATH", "/vault-approle/secret_id"))
TRANSIT_KEY = os.environ.get("TRANSIT_KEY", "app-key")
DATA_DIR = Path(os.environ.get("DATA_DIR", "data"))
DATA_FILE = Path(os.environ.get("DATA_FILE") or (DATA_DIR / "encrypted_records.json"))

app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "transit-demo-secret")


def load_approle_ids():
    missing = []
    role_id = secret_id = None

    if ROLE_ID_PATH.exists():
        role_id = ROLE_ID_PATH.read_text().strip()
    else:
        missing.append(str(ROLE_ID_PATH))

    if SECRET_ID_PATH.exists():
        secret_id = SECRET_ID_PATH.read_text().strip()
    else:
        missing.append(str(SECRET_ID_PATH))

    if missing:
        raise FileNotFoundError(
            "AppRole credentials missing. Expected files: " + ", ".join(missing)
        )

    if not role_id or not secret_id:
        raise ValueError("AppRole credentials are empty")

    return role_id, secret_id


def ensure_data_store():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    if not DATA_FILE.exists():
        DATA_FILE.write_text("[]", encoding="utf-8")


def load_records():
    ensure_data_store()
    try:
        raw = DATA_FILE.read_text(encoding="utf-8").strip()
        if not raw:
            return []
        return json.loads(raw)
    except json.JSONDecodeError:
        return []


def save_records(records):
    ensure_data_store()
    DATA_FILE.write_text(json.dumps(records, indent=2), encoding="utf-8")


def current_timestamp():
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def get_vault_client():
    role_id, secret_id = load_approle_ids()
    client = hvac.Client(url=VAULT_ADDR)
    client.auth.approle.login(role_id=role_id, secret_id=secret_id)
    return client


def encrypt_plaintext(plaintext: str):
    client = get_vault_client()
    b64_plaintext = base64.b64encode(plaintext.encode()).decode()
    result = client.secrets.transit.encrypt_data(
        name=TRANSIT_KEY,
        plaintext=b64_plaintext,
    )
    return result["data"]["ciphertext"]


def decrypt_ciphertext(ciphertext: str):
    client = get_vault_client()
    result = client.secrets.transit.decrypt_data(
        name=TRANSIT_KEY,
        ciphertext=ciphertext,
    )
    b64_plaintext = result["data"].get("plaintext")
    if not b64_plaintext:
        raise ValueError("Decrypt response missing plaintext")
    return base64.b64decode(b64_plaintext).decode()


@app.route("/", methods=["GET", "POST"])
def index():
    records = load_records()
    decrypted_output = None
    selected_record_id = None
    plaintext_draft = ""

    if request.method == "POST":
        action = request.form.get("action")
        plaintext_draft = request.form.get("plaintext", "")
        try:
            if action == "encrypt":
                plaintext = plaintext_draft.strip()
                if not plaintext:
                    raise ValueError("Plaintext cannot be empty")
                ciphertext = encrypt_plaintext(plaintext)
                record = {
                    "id": str(uuid.uuid4()),
                    "ciphertext": ciphertext,
                    "created_at": current_timestamp(),
                }
                records.insert(0, record)
                save_records(records)
                plaintext_draft = ""
                flash("Secret encrypted and stored on disk.", "success")
            elif action == "decrypt":
                record_id = request.form.get("record_id", "").strip()
                if not record_id:
                    raise ValueError("Select a record to decrypt")
                selected_record_id = record_id
                record = next((item for item in records if item["id"] == record_id), None)
                if not record:
                    raise ValueError("Record not found")
                decrypted_output = decrypt_ciphertext(record["ciphertext"])
                flash("Ciphertext decrypted on demand.", "success")
            else:
                raise ValueError("Unknown action")
        except (FileNotFoundError, ValueError) as exc:
            flash(str(exc), "error")
        except Exception as exc:  # pragma: no cover
            flash(f"Unexpected error: {exc}", "error")

    return render_template(
        "index.html",
        records=records,
        decrypted_output=decrypted_output,
        selected_record_id=selected_record_id,
        plaintext_value=plaintext_draft,
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
