"""Validate OpenAPI and shared wire examples without contacting an API server."""
import json
from pathlib import Path

import yaml
from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate_spec


def main():
    root = Path(__file__).resolve().parents[2]
    spec = yaml.safe_load((root / 'docs/contracts/openapi.yaml').read_text(encoding='utf-8'))
    # All references are local: contract validation must not download arbitrary schemas.
    def check_refs(value):
        if isinstance(value, dict):
            if '$ref' in value:
                ref = value['$ref']
                assert ref.startswith('#/'), f'Non-local reference: {ref}'
                target = spec
                for key in ref[2:].split('/'):
                    target = target[key.replace('~1', '/').replace('~0', '~')]
            for item in value.values():
                check_refs(item)
        elif isinstance(value, list):
            for item in value:
                check_refs(item)
    check_refs(spec)
    validate_spec(spec)
    assert spec['servers'] == [{'url': '/v1'}]
    operation_ids = set()
    for path, methods in spec['paths'].items():
        for method, operation in methods.items():
            if method not in {'get', 'post', 'put', 'patch', 'delete', 'head', 'options', 'trace'}:
                continue  # Path-level parameters are validated by validate_spec above.
            parameters = methods.get('parameters', []) + operation.get('parameters', [])
            identifier = operation['operationId']
            assert identifier not in operation_ids, identifier
            operation_ids.add(identifier)
            assert operation['x-implementation-status'] in ('implemented', 'planned')
            if operation.get('security', spec['security']):
                assert {'$ref': '#/components/parameters/DeviceId'} in parameters, path
            if operation['x-implementation-status'] == 'planned' and method != 'get':
                assert {'$ref': '#/components/parameters/IdempotencyKey'} in parameters, path
    def validator(name):
        schema = {'$ref': '#/components/schemas/' + name, 'components': spec['components']}
        Draft202012Validator.check_schema(schema)
        return Draft202012Validator(schema, format_checker=FormatChecker())
    for schema in spec['components']['schemas'].values():
        Draft202012Validator.check_schema(schema)
    wire = json.loads((root / 'fixtures/contracts/api-wire.json').read_text(encoding='utf-8'))
    for key, name in {
        'authSession': 'AuthSession', 'loginRequest': 'LoginRequest',
        'refreshRequest': 'RefreshRequest', 'linkBegin': 'LinkBegin',
        'linkProof': 'LinkProof', 'linkChallenge': 'LinkChallenge', 'error': 'ApiErrorResponse',
    }.items():
        validator(name).validate(wire[key])
    for name, values in wire['enums'].items():
        assert spec['components']['schemas'][name]['enum'] == values, name
    cases = json.loads((root / 'fixtures/contracts/api-schema-cases.json').read_text(encoding='utf-8'))
    for index, case in enumerate(cases, 1):
        errors = list(validator(case['schema']).iter_errors(case['value']))
        assert (not errors) == case['valid'], f"Case {index} ({case['schema']}) failed: {errors}"
    print(f'PASS: OpenAPI, local references, security, 7 wire examples, {len(cases)} schema boundary cases')


if __name__ == '__main__':
    main()
