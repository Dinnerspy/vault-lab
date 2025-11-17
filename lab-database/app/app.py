import os
from pathlib import Path

import hvac
import psycopg
from flask import Flask, render_template, request

VAULT_ADDR = os.environ.get("VAULT_ADDR", "http://vault:8200")
ROLE_ID_PATH = Path(os.environ.get("ROLE_ID_PATH", "/vault-approle/role_id"))
SECRET_ID_PATH = Path(os.environ.get("SECRET_ID_PATH", "/vault-approle/secret_id"))
DB_HOST = os.environ.get("DB_HOST", "postgres")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "appdb")

app = Flask(__name__)

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


def fetch_db_creds():
    role_id, secret_id = load_approle_ids()

    client = hvac.Client(url=VAULT_ADDR)
    client.auth.approle.login(role_id=role_id, secret_id=secret_id)

    secret = client.secrets.database.generate_credentials(name="app-role")
    data = secret["data"]
    return {
        "username": data["username"],
        "password": data["password"],
    }


def run_query(creds):
    conn = psycopg.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=creds["username"],
        password=creds["password"],
        connect_timeout=5,
    )
    with conn, conn.cursor() as cur:
        cur.execute("SELECT id, secret_value, created_at FROM app_secrets ORDER BY id")
        rows = cur.fetchall()
    return rows


@app.route("/", methods=["GET", "POST"])
def index():
    rows = []
    creds = None
    error = None

    if request.method == "POST":
        try:
            creds = fetch_db_creds()
            rows = run_query(creds)
        except (FileNotFoundError, ValueError) as exc:
            error = str(exc)
        except Exception as exc:  # pragma: no cover
            error = f"Unexpected error: {exc}"

    return render_template("index.html", rows=rows, creds=creds, error=error)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)
