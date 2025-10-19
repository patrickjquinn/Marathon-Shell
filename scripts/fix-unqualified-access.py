#!/usr/bin/env python3
"""
Automated QML Unqualified Access Fixer
Fixes unqualified access warnings by adding explicit ID references.
"""

import re
import sys
from pathlib import Path
from typing import List, Tuple, Dict

class QMLFixer:
    def __init__(self, dry_run=True):
        self.dry_run = dry_run
        self.stats = {
            "files_processed": 0,
            "files_modified": 0,
            "ids_added": 0,
            "references_qualified": 0,
            "errors": []
        }
    
    def find_root_component(self, content: str) -> Tuple[str, int, int]:
        """Find the root QML component and its brace positions."""
        # Match: ComponentName {
        pattern = r'^([A-Z][A-Za-z0-9]*)\s*\{'
        match = re.search(pattern, content, re.MULTILINE)
        if not match:
            return None, -1, -1
        
        component_name = match.group(1)
        start_pos = match.end() - 1  # Position of opening brace
        
        # Find matching closing brace
        brace_count = 1
        pos = start_pos + 1
        while pos < len(content) and brace_count > 0:
            if content[pos] == '{':
                brace_count += 1
            elif content[pos] == '}':
                brace_count -= 1
            pos += 1
        
        end_pos = pos - 1 if brace_count == 0 else -1
        return component_name, start_pos, end_pos
    
    def has_root_id(self, content: str, start_pos: int) -> bool:
        """Check if root component already has an ID."""
        # Look for 'id: something' in the first few lines after opening brace
        search_area = content[start_pos:start_pos + 500]
        return bool(re.search(r'^\s*id:\s*\w+', search_area, re.MULTILINE))
    
    def add_root_id(self, content: str, start_pos: int) -> str:
        """Add 'id: root' after the opening brace of root component."""
        # Find the position after opening brace and any whitespace
        insert_pos = start_pos + 1
        while insert_pos < len(content) and content[insert_pos] in ' \t':
            insert_pos += 1
        
        # Add newline if not already there
        if content[insert_pos] != '\n':
            new_content = content[:insert_pos] + '\n    id: root\n' + content[insert_pos:]
        else:
            insert_pos += 1
            new_content = content[:insert_pos] + '    id: root\n' + content[insert_pos:]
        
        return new_content
    
    def find_properties_and_functions(self, content: str) -> Dict[str, List[str]]:
        """Extract property and function names from the file."""
        properties = []
        functions = []
        
        # Find properties: property type name: value
        prop_pattern = r'^\s*(?:readonly\s+)?property\s+\w+\s+(\w+)(?:\s*:\s*.+)?$'
        for match in re.finditer(prop_pattern, content, re.MULTILINE):
            properties.append(match.group(1))
        
        # Find functions: function name()
        func_pattern = r'^\s*function\s+(\w+)\s*\('
        for match in re.finditer(func_pattern, content, re.MULTILINE):
            functions.append(match.group(1))
        
        return {"properties": properties, "functions": functions}
    
    def qualify_access(self, content: str, symbols: Dict[str, List[str]]) -> Tuple[str, int]:
        """Add 'root.' prefix to unqualified property/function access."""
        modified_content = content
        changes = 0
        
        # Patterns to match unqualified access (very conservative)
        for prop in symbols["properties"]:
            # Match property access but not when defining it or after dot
            pattern = r'(?<![.\w])(' + re.escape(prop) + r')(?=\s*[=+\-*/&|<>!?:]|\s*\)|\s*\}|\s*,)'
            
            def replacer(match):
                nonlocal changes
                line_start = modified_content.rfind('\n', 0, match.start()) + 1
                line = modified_content[line_start:modified_content.find('\n', match.start())]
                
                # Don't replace if it's a property definition or id declaration
                if 'property' in line or 'id:' in line:
                    return match.group(0)
                
                changes += 1
                return 'root.' + match.group(1)
            
            # Only replace if we found the property
            if prop in content:
                modified_content = re.sub(pattern, replacer, modified_content)
        
        return modified_content, changes
    
    def process_file(self, file_path: Path) -> bool:
        """Process a single QML file."""
        try:
            content = file_path.read_text(encoding='utf-8')
            original_content = content
            
            # Find root component
            component_name, start_pos, end_pos = self.find_root_component(content)
            if component_name is None:
                return False
            
            # Check if root component already has an ID
            if not self.has_root_id(content, start_pos):
                print(f"  → Adding 'id: root' to {component_name}")
                content = self.add_root_id(content, start_pos)
                self.stats["ids_added"] += 1
            else:
                print(f"  → {component_name} already has an id")
            
            # Extract symbols (disabled for now - too risky)
            # symbols = self.find_properties_and_functions(content)
            # content, changes = self.qualify_access(content, symbols)
            # self.stats["references_qualified"] += changes
            
            # Write back if changed
            if content != original_content:
                if not self.dry_run:
                    file_path.write_text(content, encoding='utf-8')
                self.stats["files_modified"] += 1
                return True
            
            return False
            
        except Exception as e:
            error_msg = f"Error processing {file_path}: {e}"
            self.stats["errors"].append(error_msg)
            print(f"  ✗ {error_msg}")
            return False
    
    def process_directory(self, directory: Path, pattern: str = "**/*.qml"):
        """Process all QML files in a directory."""
        files = list(directory.glob(pattern))
        print(f"Found {len(files)} QML files\n")
        
        for file_path in files:
            print(f"Processing: {file_path.relative_to(directory)}")
            self.stats["files_processed"] += 1
            self.process_file(file_path)
            print()
    
    def print_summary(self):
        """Print summary statistics."""
        print("\n" + "=" * 60)
        print("SUMMARY")
        print("=" * 60)
        print(f"Files processed:        {self.stats['files_processed']}")
        print(f"Files modified:         {self.stats['files_modified']}")
        print(f"IDs added:              {self.stats['ids_added']}")
        print(f"References qualified:   {self.stats['references_qualified']}")
        print(f"Errors:                 {len(self.stats['errors'])}")
        
        if self.stats['errors']:
            print("\nErrors:")
            for error in self.stats['errors']:
                print(f"  - {error}")
        
        if self.dry_run:
            print("\n⚠️  DRY RUN - No files were actually modified")
        print()


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Fix QML unqualified access warnings")
    parser.add_argument("directory", type=Path, help="Directory containing QML files")
    parser.add_argument("--no-dry-run", action="store_true", help="Actually modify files (default is dry-run)")
    parser.add_argument("--pattern", default="**/*.qml", help="File pattern to match")
    
    args = parser.parse_args()
    
    if not args.directory.exists():
        print(f"Error: Directory '{args.directory}' does not exist")
        sys.exit(1)
    
    fixer = QMLFixer(dry_run=not args.no_dry_run)
    
    print("QML Unqualified Access Fixer")
    print("=" * 60)
    print(f"Directory: {args.directory}")
    print(f"Pattern:   {args.pattern}")
    print(f"Mode:      {'LIVE' if args.no_dry_run else 'DRY RUN'}")
    print("=" * 60)
    print()
    
    fixer.process_directory(args.directory, args.pattern)
    fixer.print_summary()


if __name__ == "__main__":
    main()

