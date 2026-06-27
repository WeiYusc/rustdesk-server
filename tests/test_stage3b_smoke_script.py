from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "smoke-api-token.sh"


def test_stage3b_smoke_script_is_reproducible_and_sanitized():
    assert SCRIPT.exists(), "scripts/smoke-api-token.sh must exist"
    text = SCRIPT.read_text()

    assert "set -euo pipefail" in text
    assert "mktemp -d" in text
    assert "trap cleanup EXIT" in text
    assert 'kill -- "-${API_PID}"' in text
    assert 'rm -rf "${VERIFY_DIR}"' in text
    assert "assert_port_free" in text
    assert 'require_file "${ROOT_DIR}/target"' in text
    assert "docker compose -f docker/compose-baseline/compose.yml" in text
    assert "127.0.0.1:24114" in text
    assert "127.0.0.1:23116" in text
    assert "127.0.0.1:23117" in text
    assert "GOFLAGS=-mod=mod" in text
    assert "setsid go run ./cmd -c ./conf/config.yaml" in text
    assert '-v "${ROOT_DIR}/target:/work/target"' in text
    assert 'RUSTDESK_API_JWT_KEY="${SMOKE_JWT_KEY}"' in text
    assert text.index("reset-admin-pwd") < text.index("go run ./cmd -c ./conf/config.yaml >")
    assert "stage3b-test-secret" not in text
    assert "192.168." not in text
    assert "0.0.0.0:" not in text
    assert "docker compose -f docker/compose-baseline/compose.yml down -v --remove-orphans" in text
