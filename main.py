# dump_code.py
import os

# Cấu hình
# ROOT_DIR = r"E:\GODOT\yugi_duel\client_yugi_duel"
ROOT_DIR = r"E:\GODOT\yugi_duel\client_yugi_duel"

OUTPUT_FILE = r"E:\GODOT\yugi_duel\out.txt"

# Các đuôi file cần dump (có thể mở rộng)
EXTENSIONS = {
    '.py', '.lark', '.afinn', 
    '.json', '.yaml', '.yml', '.toml',
    '.ini', '.cfg', '.conf',
    '.html', '.css', '.js', '.ts',
    '.c', '.cpp', '.h', '.hpp', '.go', '.java', '.rs', '.gd'
}

# Các thư mục nên bỏ qua
SKIP_DIRS = {
    '__pycache__', '.git', 'node_modules', '.vscode', '.idea', 'venv', 'env', 'v3.1', 'tool'
}

def should_include_file(filepath):
    """Kiểm tra file có nên được dump không"""
    _, ext = os.path.splitext(filepath)
    return ext.lower() in EXTENSIONS

def is_binary(filepath):
    """Kiểm tra file có phải binary không"""
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            f.read(1024)
        return False
    except UnicodeDecodeError:
        return True
    except Exception:
        return True  # nếu lỗi, bỏ qua

def dump_code():
    with open(OUTPUT_FILE, 'w', encoding='utf-8') as out:
        out.write(f"=== DUMP CODE TỪ: {ROOT_DIR} ===\n")
        out.write(f"Chỉ dump các file: {', '.join(sorted(EXTENSIONS))}\n")
        out.write("=" * 80 + "\n\n")

        for root, dirs, files in os.walk(ROOT_DIR):
            # Lọc các thư mục cần bỏ qua
            dirs[:] = [d for d in dirs if d not in SKIP_DIRS]

            for file in files:
                filepath = os.path.join(root, file)
                relpath = os.path.relpath(filepath, ROOT_DIR)

                if should_include_file(filepath):
                    if is_binary(filepath):
                        print(f"[SKIP] Binary file: {relpath}")
                        continue

                    try:
                        with open(filepath, 'r', encoding='utf-8') as f:
                            content = f.read()
                        out.write(f"--- FILE: {relpath} ---\n")
                        out.write(content)
                        out.write("\n" + "="*80 + "\n\n")
                        print(f"[OK] Dumped: {relpath}")
                    except Exception as e:
                        print(f"[ERROR] Đọc file {relpath} thất bại: {e}")
                        out.write(f"[ERROR] Không thể đọc file: {relpath}\n\n")

    print(f"\n✅ Đã xuất toàn bộ code vào: {OUTPUT_FILE}")

if __name__ == "__main__":
    dump_code()