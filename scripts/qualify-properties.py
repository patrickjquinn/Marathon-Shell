#!/usr/bin/env python3
"""
Automated QML Unqualified Access Fixer - Phase 2
Fixes unqualified property access within property bindings.
"""

import re
import sys
from pathlib import Path
from typing import List, Tuple, Set

class QMLQualifier:
    def __init__(self, dry_run=True, verbose=False):
        self.dry_run = dry_run
        self.verbose = verbose
        self.stats = {
            "files_processed": 0,
            "files_modified": 0,
            "properties_qualified": 0,
            "errors": []
        }
    
    def extract_root_properties(self, content: str) -> Set[str]:
        """Extract all property names defined at root level."""
        properties = set()
        
        # Find root component opening brace
        root_match = re.search(r'^[A-Z][A-Za-z0-9]*\s*\{', content, re.MULTILINE)
        if not root_match:
            return properties
        
        # Extract properties from root level (not nested)
        # Match: property type name or readonly property type name
        pattern = r'^\s{0,8}(?:readonly\s+)?property\s+\w+\s+(\w+)'
        
        for match in re.finditer(pattern, content, re.MULTILINE):
            prop_name = match.group(1)
            # Exclude common built-in properties
            if prop_name not in ['parent', 'children', 'data', 'resources', 'states', 'transitions']:
                properties.add(prop_name)
        
        return properties
    
    def qualify_property_access(self, content: str, properties: Set[str]) -> Tuple[str, int]:
        """Add 'root.' prefix to unqualified property access."""
        modified_content = content
        changes = 0
        
        for prop in properties:
            # Pattern: property name followed by comparison, arithmetic, or end of expression
            # But NOT when:
            # - It's part of a property definition
            # - It's after a dot (already qualified)
            # - It's being assigned to (prop:)
            # - It's in a string
            
            pattern = (
                r'(?<![.\w"\'])'  # Not after dot, word char, or quotes
                r'\b(' + re.escape(prop) + r')\b'  # The property name as whole word
                r'(?!'  # Not followed by:
                r'\s*:'  # assignment operator
                r'|\s*\('  # function call parentheses
                r')'
                r'(?='  # Must be followed by:
                r'\s*[=!<>+\-*/&|?]'  # operator
                r'|\s*\)'  # closing paren
                r'|\s*}'  # closing brace
                r'|\s*,'  # comma
                r'|\s*\?'  # ternary operator
                r'|\s*\n'  # newline
                r')'
            )
            
            def replacer(match):
                nonlocal changes
                line_start = modified_content.rfind('\n', 0, match.start()) + 1
                line_end = modified_content.find('\n', match.start())
                if line_end == -1:
                    line_end = len(modified_content)
                line = modified_content[line_start:line_end]
                
                # Skip if it's a property definition or id declaration
                if re.search(r'^\s*(?:readonly\s+)?property\s+', line) or 'id:' in line:
                    return match.group(0)
                
                # Skip if already qualified
                if 'root.' in line[:match.start() - line_start]:
                    return match.group(0)
                
                # Skip if in a comment
                comment_pos = line.find('//')
                if comment_pos != -1 and comment_pos < (match.start() - line_start):
                    return match.group(0)
                
                changes += 1
                if self.verbose:
                    print(f"      Line {modified_content[:match.start()].count(chr(10)) + 1}: {prop} → root.{prop}")
                return 'root.' + match.group(1)
            
            modified_content = re.sub(pattern, replacer, modified_content)
        
        return modified_content, changes
    
    def process_file(self, file_path: Path) -> bool:
        """Process a single QML file."""
        try:
            content = file_path.read_text(encoding='utf-8')
            original_content = content
            
            # Extract root properties
            properties = self.extract_root_properties(content)
            if not properties:
                if self.verbose:
                    print(f"  → No properties found")
                return False
            
            if self.verbose:
                print(f"  → Found {len(properties)} properties: {', '.join(sorted(properties))}")
            
            # Qualify unqualified access
            content, changes = self.qualify_property_access(content, properties)
            
            if changes > 0:
                print(f"  → Qualified {changes} property accesses")
                self.stats["properties_qualified"] += changes
                
                if not self.dry_run:
                    file_path.write_text(content, encoding='utf-8')
                self.stats["files_modified"] += 1
                return True
            else:
                print(f"  → No unqualified access found")
            
            return False
            
        except Exception as e:
            error_msg = f"Error processing {file_path}: {e}"
            self.stats["errors"].append(error_msg)
            print(f"  ✗ {error_msg}")
            return False
    
    def process_directory(self, directory: Path, pattern: str = "*.qml", limit: int = None):
        """Process QML files in a directory."""
        files = sorted(directory.glob(pattern))
        if limit:
            files = files[:limit]
        
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
        print(f"Properties qualified:   {self.stats['properties_qualified']}")
        print(f"Errors:                 {len(self.stats['errors'])}")
        
        if self.stats['errors']:
            print("\nErrors:")
            for error in self.stats['errors'][:10]:
                print(f"  - {error}")
            if len(self.stats['errors']) > 10:
                print(f"  ... and {len(self.stats['errors']) - 10} more")
        
        if self.dry_run:
            print("\n⚠️  DRY RUN - No files were actually modified")
        print()


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description="Fix QML unqualified access warnings")
    parser.add_argument("directory", type=Path, help="Directory containing QML files")
    parser.add_argument("--no-dry-run", action="store_true", help="Actually modify files")
    parser.add_argument("--pattern", default="*.qml", help="File pattern to match")
    parser.add_argument("--limit", type=int, help="Limit number of files to process")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    args = parser.parse_args()
    
    if not args.directory.exists():
        print(f"Error: Directory '{args.directory}' does not exist")
        sys.exit(1)
    
    qualifier = QMLQualifier(dry_run=not args.no_dry_run, verbose=args.verbose)
    
    print("QML Unqualified Access Qualifier")
    print("=" * 60)
    print(f"Directory: {args.directory}")
    print(f"Pattern:   {args.pattern}")
    print(f"Mode:      {'LIVE' if args.no_dry_run else 'DRY RUN'}")
    if args.limit:
        print(f"Limit:     {args.limit} files")
    print("=" * 60)
    print()
    
    qualifier.process_directory(args.directory, args.pattern, args.limit)
    qualifier.print_summary()


if __name__ == "__main__":
    main()

