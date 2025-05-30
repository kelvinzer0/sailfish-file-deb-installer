#!/bin/bash

# DEB Package Installer untuk Sailfish OS/Ubuntu Ports (aarch64)
# Untuk mengekstrak dan install .deb ke environment Linux
# Memperbaiki masalah path binary dan library

set -e

# Warna
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Cleanup fungsi
cleanup() {
    if [ -d "$TEMP_DIR" ]; then
        print_info "Membersihkan temporary folder..."
        rm -rf "$TEMP_DIR"
    fi
}
trap cleanup EXIT

# Validasi argumen
if [ $# -eq 0 ]; then
    print_error "Gunakan: $0 <file.deb> [target_prefix]"
    print_info "Contoh: $0 package.deb /usr/local"
    exit 1
fi

# Handle path file .deb dengan benar
if ! DEB_FILE=$(realpath "$1" 2>/dev/null); then
    DEB_FILE="$(cd "$(dirname "$1")"; pwd)/$(basename "$1")"
fi

# Target prefix (default: /usr/local)
TARGET_PREFIX="${2:-/usr/local}"
TEMP_DIR="/tmp/deb_install_$$"
BACKUP_DIR="$TEMP_DIR/backup"

if [ ! -f "$DEB_FILE" ]; then
    print_error "File $DEB_FILE tidak ditemukan."
    exit 1
fi

if [[ ! "$DEB_FILE" =~ \.deb$ ]]; then
    print_error "File harus berekstensi .deb"
    exit 1
fi

print_info "Menyiapkan instalasi $DEB_FILE ke $TARGET_PREFIX..."
mkdir -p "$TEMP_DIR" "$BACKUP_DIR"
cd "$TEMP_DIR"

# Ekstrak file .deb
print_info "Mengekstrak file .deb..."
ar x "$DEB_FILE"

# Ekstrak data.tar.*
if [ -f "data.tar.xz" ]; then
    tar -xJf data.tar.xz
elif [ -f "data.tar.gz" ]; then
    tar -xzf data.tar.gz
elif [ -f "data.tar" ]; then
    tar -xf data.tar
else
    print_error "data.tar.* tidak ditemukan dalam .deb"
    exit 1
fi

# Fungsi untuk backup file yang sudah ada
backup_existing() {
    local target_path="$TARGET_PREFIX/$1"
    if [ -e "$target_path" ]; then
        local backup_path="$BACKUP_DIR/$1"
        mkdir -p "$(dirname "$backup_path")"
        mv -v "$target_path" "$backup_path"
    fi
}

# Fungsi untuk memeriksa dan skip library/binary tertentu
should_skip() {
    local file_path="$1"
    
    # Skip dynamic linker/loader (ld)
    if [[ "$file_path" == *"/ld-linux"* ]] || [[ "$file_path" == *"/ld.so"* ]] || [[ "$file_path" == *"/ld-"* ]]; then
        print_warning "Melewati instalasi ld/loader: $file_path"
        return 0
    fi
    
    # Skip library system penting
    if [[ "$file_path" == *"/libc.so"* ]] || [[ "$file_path" == *"/libstdc++"* ]] || 
       [[ "$file_path" == *"/libgcc_s.so"* ]] || [[ "$file_path" == *"/libm.so"* ]]; then
        print_warning "Melewati library system: $file_path"
        return 0
    fi
    
    # Skip jika file sudah ada dan kita tidak ingin menimpa
    local dest_path="$TARGET_PREFIX/${file_path#usr/}"
    if [ -e "$dest_path" ] && [ "$OVERWRITE_EXISTING" != "1" ]; then
        print_warning "File sudah ada, melewati: $dest_path"
        return 0
    fi
    
    return 1
}

# Copy isi yang ditemukan ke target prefix dengan penanganan khusus
copy_if_exists() {
    local src_path="$1"
    local dest_rel_path="$2"
    
    if [ -e "$src_path" ]; then
        if [ -d "$src_path" ]; then
            # Handle directories
            find "$src_path" -type f -o -type l | while read -r file; do
                local rel_path="${file#$src_path/}"
                local dest_path="$TARGET_PREFIX/$dest_rel_path/$rel_path"
                
                if should_skip "$file"; then
                    continue
                fi
                
                mkdir -p "$(dirname "$dest_path")"
                cp -fv "$file" "$dest_path"
                
                # Set permission yang sesuai
                chmod 755 "$dest_path" 2>/dev/null || true
            done
        else
            # Handle single files
            if should_skip "$src_path"; then
                return
            fi
            
            local dest_path="$TARGET_PREFIX/$dest_rel_path"
            mkdir -p "$(dirname "$dest_path")"
            cp -fv "$src_path" "$dest_path"
            
            # Set permission yang sesuai
            chmod 755 "$dest_path" 2>/dev/null || true
        fi
    fi
}

print_info "Memindahkan file ke target prefix..."

# Backup file penting yang mungkin ditimpa
backup_existing "bin/ld"
backup_existing "lib/ld-linux-aarch64.so.1"
backup_existing "lib64/ld-linux-aarch64.so.1"

# Pindahkan path standar dari folder hasil ekstrak
copy_if_exists "usr/bin" "bin"
copy_if_exists "usr/sbin" "sbin"
copy_if_exists "usr/lib" "lib"
copy_if_exists "usr/lib/aarch64-linux-gnu" "lib"
copy_if_exists "usr/lib64" "lib64"
copy_if_exists "usr/libexec" "libexec"
copy_if_exists "usr/include" "include"
copy_if_exists "usr/share" "share"
copy_if_exists "etc" "etc"

# Restore file penting yang tidak ingin diupdate
if [ -f "$BACKUP_DIR/bin/ld" ]; then
    print_info "Mengembalikan ld binary original..."
    mv -v "$BACKUP_DIR/bin/ld" "$TARGET_PREFIX/bin/ld"
fi

if [ -f "$BACKUP_DIR/lib/ld-linux-aarch64.so.1" ]; then
    print_info "Mengembalikan ld-linux-aarch64.so.1 original..."
    mv -v "$BACKUP_DIR/lib/ld-linux-aarch64.so.1" "$TARGET_PREFIX/lib/ld-linux-aarch64.so.1"
fi

if [ -f "$BACKUP_DIR/lib64/ld-linux-aarch64.so.1" ]; then
    print_info "Mengembalikan ld-linux-aarch64.so.1 (lib64) original..."
    mv -v "$BACKUP_DIR/lib64/ld-linux-aarch64.so.1" "$TARGET_PREFIX/lib64/ld-linux-aarch64.so.1"
fi

# Update library cache
print_info "Memperbarui cache library..."
ldconfig 2>/dev/null || true

print_success "Instalasi selesai untuk $DEB_FILE"
print_info "Backup file yang ditimpa disimpan di: $BACKUP_DIR"
