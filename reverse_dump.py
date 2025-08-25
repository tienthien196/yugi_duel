# reverse_dump.py
import os
import re

# Cấu hình
INPUT_DUMP_FILE = r"E:\GODOT\yugi_duel\out.txt"
OUTPUT_ROOT = r"E:\GODOT\yugi_duel\src_recovered"

# Mẫu để nhận diện đầu file: "--- FILE: path/to/file.ext ---"
FILE_HEADER_PATTERN = re.compile(r"^--- FILE: (.*?) ---$")

def extract_files_from_dump():
    """Trích xuất các file từ file dump"""
    print(f"Đang đọc file dump: {INPUT_DUMP_FILE}")
    
    try:
        with open(INPUT_DUMP_FILE, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"[LỖI] Không thể đọc file dump: {e}")
        return

    # Tách nội dung theo các dấu phân cách (80 dấu =)
    sections = re.split(r"={80}\n\n", content)

    file_count = 0
    for section in sections:
        lines = section.strip().splitlines()
        if not lines:
            continue

        # Kiểm tra dòng đầu tiên có phải là header không
        match = FILE_HEADER_PATTERN.match(lines[0])
        if not match:
            # Bỏ qua các phần không phải file (giới thiệu, lỗi,...)
            continue

        relpath = match.group(1).strip()
        file_content = '\n'.join(lines[1:])  # Nội dung file (bỏ header)

        # Tạo đường dẫn đầy đủ
        fullpath = os.path.join(OUTPUT_ROOT, relpath)
        os.makedirs(os.path.dirname(fullpath), exist_ok=True)

        try:
            with open(fullpath, 'w', encoding='utf-8') as f:
                f.write(file_content)
            print(f"[OK] Đã tạo lại file: {relpath}")
            file_count += 1
        except Exception as e:
            print(f"[ERROR] Ghi file {relpath} thất bại: {e}")

    print(f"\n✅ Hoàn tất! Đã khôi phục {file_count} file vào: {OUTPUT_ROOT}")

if __name__ == "__main__":
    extract_files_from_dump()