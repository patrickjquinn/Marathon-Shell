#!/usr/bin/env python3
import sys
import os

def validate_qmldir(qmldir_path):
    print(f"Validating {qmldir_path}...")
    base_dir = os.path.dirname(qmldir_path)
    
    with open(qmldir_path, 'r') as f:
        lines = f.readlines()
        
    has_module = False
    errors = []
    
    for i, line in enumerate(lines):
        line = line.strip()
        if not line or line.startswith('#'):
            continue
            
        parts = line.split()
        
        # Check for valid keywords
        if parts[0] == "module":
            has_module = True
            continue
        elif parts[0] == "plugin":
            continue
        elif parts[0] == "typeinfo":
            continue
        elif parts[0] == "designersupported":
            continue
        elif parts[0] == "depends":
            continue
        elif parts[0] == "import":
            continue
            
        # Component definition: Type Version File
        # Example: TerminalSession 1.0 TerminalSession.qml
        # Singleton definition: singleton Type Version File
        if parts[0] == "singleton":
             if len(parts) >= 4:
                 filename = parts[-1]
                 file_path = os.path.join(base_dir, filename)
                 if not os.path.exists(file_path):
                    errors.append(f"Line {i+1}: File not found: {filename}")
                 
                 # Check version
                 version = parts[2]
                 if not version[0].isdigit():
                     errors.append(f"Line {i+1}: Invalid version format: {version}")
             else:
                 errors.append(f"Line {i+1}: Invalid singleton definition")
             continue

        # Component definition: Type Version File
        # Example: TerminalSession 1.0 TerminalSession.qml
        if len(parts) >= 3:
                 # Suspicious line
                 # Check if it looks like QML code (e.g. "import QtQuick")
                 if "{" in line or "}" in line or ";" in line:
                     errors.append(f"Line {i+1}: Suspicious content (looks like QML code?): {line}")

    if errors:
        print(f"❌ Validation FAILED for {qmldir_path}:")
        for e in errors:
            print(f"  - {e}")
        return False
    
    print("✅ Valid")
    return True

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: validate_qmldir.py <path_to_qmldir> [path_to_qmldir ...]")
        sys.exit(1)
        
    success = True
    for path in sys.argv[1:]:
        if not validate_qmldir(path):
            success = False
            
    sys.exit(0 if success else 1)
