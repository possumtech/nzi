#!/usr/bin/env python3
import sys
import os
from lxml import etree, isoschematron

def lint_file(xml_path, xsd_path, sch_path):
    print(f"Linting {xml_path}...")
    
    try:
        # Load XML
        with open(xml_path, 'rb') as f:
            xml_doc = etree.XML(f.read())
            
        # 1. XSD Validation
        with open(xsd_path, 'rb') as f:
            schema_doc = etree.XML(f.read())
            schema = etree.XMLSchema(schema_doc)
            if not schema.validate(xml_doc):
                print(f"ERROR: XSD Validation failed for {xml_path}")
                for error in schema.error_log:
                    print(f"  Line {error.line}: {error.message}")
                return False
            print("  [PASS] XSD Validation")

        # 2. Schematron Validation
        with open(sch_path, 'rb') as f:
            sch_doc = etree.XML(f.read())
            schematron = isoschematron.Schematron(sch_doc)
            if not schematron.validate(xml_doc):
                print(f"ERROR: Schematron Validation failed for {xml_path}")
                # Get the validation report (SVRL)
                report = schematron.validation_report
                for failed_assert in report.xpath('//svrl:failed-assert', namespaces={'svrl': 'http://purl.oclc.org/dsdl/svrl'}):
                    text = failed_assert.xpath('./svrl:text', namespaces={'svrl': 'http://purl.oclc.org/dsdl/svrl'})[0].text
                    print(f"  [FAIL] {text.strip()}")
                return False
            print("  [PASS] Schematron Validation")
            
        return True

    except Exception as e:
        print(f"ERROR: Failed to process {xml_path}: {e}")
        return False

def main():
    if len(sys.argv) < 2:
        # If no files provided, lint all in test/turns
        turns_dir = "test/turns"
        files = [os.path.join(turns_dir, f) for f in os.listdir(turns_dir) if f.endswith(".xml")]
    else:
        files = sys.argv[1:]

    xsd_path = "nzi.xsd"
    sch_path = "nzi.sch"
    
    success = True
    for xml_path in files:
        if not lint_file(xml_path, xsd_path, sch_path):
            success = False
            
    if not success:
        sys.exit(1)
    print("\nAll files passed linting.")

if __name__ == "__main__":
    main()
