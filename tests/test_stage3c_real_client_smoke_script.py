from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "smoke-real-client-register.sh"


def test_stage3c_real_client_smoke_script_is_reproducible_and_bounded():
    assert SCRIPT.exists(), "scripts/smoke-real-client-register.sh must exist"
    text = SCRIPT.read_text()

    assert "set -euo pipefail" in text
    assert "mktemp -d" in text
    assert "trap cleanup EXIT" in text
    assert 'kill -- "-${CLIENT_SESSION_PID}"' in text
    assert "pkill -f" not in text
    assert "RUSTDESK_CLIENT_APPIMAGE_URL" in text
    assert "RUSTDESK_CLIENT_APPIMAGE_SHA256" in text
    assert "sha256sum -c -" in text
    assert "rustdesk-1.4.8-x86_64.AppImage" in text
    assert "docker compose -f docker/compose-baseline/compose.yml" in text
    assert "127.0.0.1:23116" in text
    assert "127.0.0.1:23117" in text
    assert "127.0.0.1:24114" in text
    assert "custom-rendezvous-server" in text
    assert "api-server" in text
    assert "xvfb-run -a" in text
    assert "exec setsid env" in text
    assert "libayatana-appindicator3" in text
    assert "ldconfig -p" in text
    assert "--server" in text
    assert "update_pk" in text
    assert "start rendezvous mediator of 127.0.0.1:23116" in text
    assert "SMOKE_REAL_CLIENT_REGISTER_PASS" in text
    assert "docker compose -f docker/compose-baseline/compose.yml down -v --remove-orphans" in text
    assert "0.0.0.0:" not in text
    assert "192.168." not in text
