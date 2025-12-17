set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SSH_DIR="$HOME/.ssh"
CFG_SRC="$PROJECT_DIR/ssh_config_per_connect.txt"
CFG_DST="$SSH_DIR/config"
BEGIN_MARK=">>> PT1.6 Hans Jeremi González Pin >>>"
END_MARK="<<< PT1.6 Hans Jeremi González Pin <<<"

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"

if [ ! -f "$CFG_SRC" ]; then
  echo "No existe $CFG_SRC. Ejecuta terraform apply primero."
  exit 1
fi

for f in "$PROJECT_DIR"/bastion.pem "$PROJECT_DIR"/private-*.pem; do
  [ -f "$f" ] || continue
  dest="$SSH_DIR/$(basename "$f")"
  cp -f "$f" "$dest"
  chmod 400 "$dest"
done

touch "$CFG_DST"
chmod 600 "$CFG_DST" || true

if grep -qF "$BEGIN_MARK" "$CFG_DST"; then
  awk -v b="$BEGIN_MARK" -v e="$END_MARK" '
    $0==b {inblock=1; next}
    $0==e {inblock=0; next}
    !inblock {print}
  ' "$CFG_DST" > "$CFG_DST.tmp"
  mv "$CFG_DST.tmp" "$CFG_DST"
fi

{
  echo "$BEGIN_MARK"
  cat "$CFG_SRC"
  echo "$END_MARK"
} >> "$CFG_DST"

echo "OK"
echo "ssh bastion"
echo "ssh private-1"
