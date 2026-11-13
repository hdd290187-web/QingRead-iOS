#!/usr/bin/env python3
"""Use screenshot attachments; Xcode must not automatically record UI videos."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET

project = Path('QingRead.xcodeproj')
text = (project / 'project.pbxproj').read_text()
targets = text.split('/* Begin PBXNativeTarget section */')[1].split('/* End PBXNativeTarget section */')[0]
identifiers = dict((name, identifier) for identifier, name in re.findall(r'([A-F0-9]{24}) /\* (QingRead(?:UI)?Tests|QingRead) \*/ = \{', targets))
assert set(identifiers) == {'QingRead', 'QingReadTests', 'QingReadUITests'}, identifiers
def target(name):
    return {'containerPath': 'container:QingRead.xcodeproj', 'identifier': identifiers[name], 'name': name}
plan = {
    'configurations': [{'id': 'F0D366A5-0583-4214-8CB0-2802E7D3D4F5', 'name': 'Test Scheme Action', 'options': {}}],
    'defaultOptions': {'preferredScreenCaptureFormat': 'screenshot', 'targetForVariableExpansion': target('QingRead')},
    'testTargets': [{'target': target(name)} for name in ['QingReadTests', 'QingReadUITests']],
    'version': 1,
}
Path('QingRead.xctestplan').write_text(json.dumps(plan, indent=2) + '\n')
scheme = project / 'xcshareddata/xcschemes/QingRead.xcscheme'
tree = ET.parse(scheme)
action = tree.getroot().find('TestAction')
assert action is not None
for tag in ['TestPlans', 'Testables']:
    for existing in action.findall(tag):
        action.remove(existing)
plans = ET.SubElement(action, 'TestPlans')
ET.SubElement(plans, 'TestPlanReference', {'reference': 'container:QingRead.xctestplan', 'default': 'YES'})
ET.indent(tree, space='  ')
tree.write(scheme, encoding='utf-8', xml_declaration=True)
print('Configured XCTest screenshot capture; automatic UI video recording disabled.')
