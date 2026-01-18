import re
import sys
import os

def remove_comments(text):
    def replacer(match):
        s = match.group(0)
        if s.startswith('/'):
            return " " # note: a space and not an empty string
        else:
            return s
    
    # Regex to capture:
    # 1. Strings (double or single quoted) to preserve them
    # 2. Block comments /* ... */
    # 3. Line comments // ...
    pattern = re.compile(
        r'//.*?$|/\*.*?\*/|\'(?:\\.|[^\\\'])*\'|"(?:\\.|[^\\"])*"',
        re.DOTALL | re.MULTILINE
    )
    return re.sub(pattern, replacer, text)

def process_file(filepath):
    try:
        with open(filepath, 'r') as f:
            content = f.read()
        
        new_content = remove_comments(content)
        
        # Simple cleanup of multiple empty lines potentially created
        new_content = re.sub(r'\n\s*\n\s*\n', '\n\n', new_content)
        
        if content != new_content:
            with open(filepath, 'w') as f:
                f.write(new_content)
            print(f"Processed: {filepath}")
    except Exception as e:
        print(f"Error processing {filepath}: {e}")

if __name__ == "__main__":
    for root, dirs, files in os.walk("."):
        if "build" in dirs:
            dirs.remove("build")
        if ".git" in dirs:
            dirs.remove(".git")
            
        for file in files:
            if file.endswith(('.cpp', '.h', '.qml', '.js')):
                process_file(os.path.join(root, file))
