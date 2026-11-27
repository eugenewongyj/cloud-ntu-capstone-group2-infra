# Capstone - Final Security Source Map

Generated from current source files.

## controller/bootstrap.py:26

[Source](../controller/bootstrap.py#L26)

```
def initialize_state(core_api):
```

SHA-256: 8abb86ee849214d82c233b4a1191f7f992e95dbcb2d25c1dbf9354fde9526c07

## controller/state.py:15

[Source](../controller/state.py#L15)

```
def initial_state():
```

SHA-256: a7bd2d2ebbdbd23713afb3ca5734413bfd7bf39cd4e93bcc84bd1825ff4e2545

## controller/state.py:75

[Source](../controller/state.py#L75)

```
result = self.core.patch_namespaced_config_map(
```

SHA-256: a7bd2d2ebbdbd23713afb3ca5734413bfd7bf39cd4e93bcc84bd1825ff4e2545

## manifests/role.yaml:27

[Source](../manifests/role.yaml#L27)

```
verbs: ["get", "patch"]
```

SHA-256: 43bd2b834a77bcb013de9dff37463f29733e84e90266dec506cc2ad2509c776f

## manifests/state-configmap.yaml:4

[Source](../manifests/state-configmap.yaml#L4)

```
name: capstone-assessment-state
```

SHA-256: 67316284ffb0478647614f0513edf08845108c65ee1d60d02ac9ca45bbb76a56

## integration/assessment-application.yaml:23

[Source](../integration/assessment-application.yaml#L23)

```
- /data/state.json
```

SHA-256: db3956f68bcf20baec3d6ac7e0b8cbc5c79b5613cd56f0fbfe027c1ec1b45cad

## integration/assessment-application.yaml:30

[Source](../integration/assessment-application.yaml#L30)

```
- RespectIgnoreDifferences=true
```

SHA-256: db3956f68bcf20baec3d6ac7e0b8cbc5c79b5613cd56f0fbfe027c1ec1b45cad

## k6/kustomization.yaml:6

[Source](../k6/kustomization.yaml#L6)

```
configMapGenerator:
```

SHA-256: 711a934ceadc19e4834057c987e0aada9327ad0be2182a74d53ef0bd20fe3599

## integration/runtime/kustomization.yaml:5

[Source](../integration/runtime/kustomization.yaml#L5)

```
- ../../k6
```

SHA-256: d87e5b451aa18d26af3763be9e1081c9e07abc5201cbfc991ca7cbe390ab568f

## CI workflow:49

[Source](../../../../.github/workflows/sre-controller-ci.yaml#L49)

```
- name: Run controller regression
```

## CI workflow:60

[Source](../../../../.github/workflows/sre-controller-ci.yaml#L60)

```
- name: Validate GitOps manifests
```

## CI workflow:98

[Source](../../../../.github/workflows/sre-controller-ci.yaml#L98)

```
if: ${{ false }}
```
