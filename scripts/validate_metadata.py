#!/usr/bin/env python3
"""
validate_metadata.py

There's no Dev Hub in CI for this repo, so this script is the whole check:
no live Apex tests, no real deploy validation, just static checks that catch
the mistakes that are easy to make by hand:

1. Every .xml file under apex/ parses as well-formed XML.
2. Every custom object referenced under apex/objects/ has an
   <object>-meta.xml file.
3. Every field-meta.xml file's <fullName> ends in __c (or __mdt fields,
   which also end in __c - the __mdt suffix is on the object, not the
   field) and the file name matches the fullName.
4. Every custom field or custom metadata type token (ending in __c or __mdt)
   referenced in an Apex class under apex/classes/ is either a declared
   field/object in apex/objects/, or is flagged as unresolved so a human
   can check it by hand. This will not catch every real deploy error - it's
   a fast sanity net, not a substitute for `sf project deploy validate`
   against a real org.

Exit code 0 means all checks passed. Any failure prints what and where,
then exits 1.
"""

import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
APEX_ROOT = REPO_ROOT / "apex"

FIELD_TOKEN_PATTERN = re.compile(r"\b[A-Za-z][A-Za-z0-9_]*__(c|mdt)\b")


def find_all_xml_files():
    return sorted(APEX_ROOT.rglob("*.xml")) + sorted(APEX_ROOT.rglob("*-meta.xml"))


def check_xml_well_formed(errors):
    xml_files = set(find_all_xml_files())
    for xml_file in sorted(xml_files):
        try:
            ET.parse(xml_file)
        except ET.ParseError as exc:
            errors.append(f"Malformed XML: {xml_file.relative_to(REPO_ROOT)} -> {exc}")


def collect_declared_objects():
    """Return {object_api_name: path} for every apex/objects/<name>/ folder."""
    objects_dir = APEX_ROOT / "objects"
    declared = {}
    if not objects_dir.exists():
        return declared
    for object_dir in objects_dir.iterdir():
        if object_dir.is_dir():
            declared[object_dir.name] = object_dir
    return declared


def check_object_meta_files_exist(declared_objects, errors):
    for name, path in declared_objects.items():
        meta_file = path / f"{name}.object-meta.xml"
        if not meta_file.exists():
            errors.append(f"Missing object-meta.xml for declared object: {path.relative_to(REPO_ROOT)}")


def collect_declared_fields(declared_objects):
    """Return {field_full_name: path} across every object's fields/ folder.

    Field names are not necessarily unique across objects (e.g. Name), so
    this is a best-effort set for the "does this token exist anywhere"
    check, not a per-object lookup.
    """
    declared_fields = {}
    for name, path in declared_objects.items():
        fields_dir = path / "fields"
        if not fields_dir.exists():
            continue
        for field_file in fields_dir.glob("*.field-meta.xml"):
            try:
                tree = ET.parse(field_file)
            except ET.ParseError:
                continue
            ns = {"sf": "http://soap.sforce.com/2006/04/metadata"}
            full_name_el = tree.find("sf:fullName", ns)
            if full_name_el is None or not full_name_el.text:
                continue
            full_name = full_name_el.text.strip()
            expected_file_name = f"{full_name}.field-meta.xml"
            if field_file.name != expected_file_name:
                declared_fields.setdefault("__filename_mismatch__", []).append(
                    f"{field_file.relative_to(REPO_ROOT)} declares fullName '{full_name}' but file is not named '{expected_file_name}'"
                )
            declared_fields[full_name] = field_file
    return declared_fields


def check_field_naming(declared_fields, errors):
    mismatches = declared_fields.pop("__filename_mismatch__", [])
    for mismatch in mismatches:
        errors.append(f"Field file name mismatch: {mismatch}")
    for full_name in declared_fields:
        if not full_name.endswith("__c"):
            errors.append(f"Custom field does not end in __c: {full_name}")


def collect_apex_field_tokens():
    """Return {token: [cls_files_it_appears_in]} for every __c/__mdt token in apex/classes/*.cls."""
    tokens = {}
    classes_dir = APEX_ROOT / "classes"
    if not classes_dir.exists():
        return tokens
    for cls_file in sorted(classes_dir.glob("*.cls")):
        text = cls_file.read_text(encoding="utf-8")
        for match in FIELD_TOKEN_PATTERN.finditer(text):
            token = match.group(0)
            tokens.setdefault(token, set()).add(cls_file.name)
    return tokens


def check_apex_tokens_resolve(declared_objects, declared_fields, warnings):
    tokens = collect_apex_field_tokens()
    known_object_names = set(declared_objects.keys())
    known_field_names = set(declared_fields.keys())

    for token, files in sorted(tokens.items()):
        if token in known_object_names or token in known_field_names:
            continue
        warnings.append(
            f"Unresolved token '{token}' referenced in {', '.join(sorted(files))} "
            f"- not found as a declared object or field under apex/objects/. "
            f"This may be a standard/managed-package field (expected for npsp__/GiftTransaction "
            f"references) or a real typo - check by hand."
        )


def main():
    errors = []
    warnings = []

    check_xml_well_formed(errors)
    declared_objects = collect_declared_objects()
    check_object_meta_files_exist(declared_objects, errors)
    declared_fields = collect_declared_fields(declared_objects)
    check_field_naming(declared_fields, errors)
    check_apex_tokens_resolve(declared_objects, declared_fields, warnings)

    if warnings:
        print(f"{len(warnings)} warning(s):")
        for warning in warnings:
            print(f"  WARN: {warning}")
        print()

    if errors:
        print(f"{len(errors)} error(s):")
        for error in errors:
            print(f"  ERROR: {error}")
        print("\nvalidate_metadata.py FAILED")
        return 1

    print(f"validate_metadata.py OK - {len(find_all_xml_files())} XML files checked, "
          f"{len(declared_objects)} objects, {len(declared_fields)} fields declared.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
