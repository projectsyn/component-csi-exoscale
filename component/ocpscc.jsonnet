// instance-specific security context constraint object for openshift
local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();

local params = inv.parameters.csi_exoscale;
local isOpenshift = std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

local openshiftScc = {
  apiVersion: 'security.openshift.io/v1',
  kind: 'SecurityContextConstraints',
  metadata: {
    name: 'csi-exoscale-scc',
    namespace: params.namespace,
    labels: {
      'app.kubernetes.io/name': 'csi-exoscale',
      'app.kubernetes.io/component': 'csi-exoscale',
      'app.kubernetes.io/managed-by': 'syn',
    },
  },
  users: [
    'system:serviceaccount:' + params.namespace + ':exoscale-csi-controller',
    'system:serviceaccount:' + params.namespace + ':exoscale-csi-node',
  ],
  volumes: [
    '*',
  ],
  allowHostDirVolumePlugin: true,
  allowHostIPC: true,
  allowHostNetwork: true,
  allowHostPID: true,
  allowHostPorts: true,
  allowPrivilegeEscalation: true,
  allowPrivilegedContainer: true,
  allowedCapabilities: [
    '*',
  ],
  allowedUnsafeSysctls: [
    '*',
  ],
  defaultAddCapabilities: null,
  fsGroup: {
    type: 'RunAsAny',
  },
  priority: null,
  runAsUser: {
    type: 'RunAsAny',
  },
  seLinuxContext: {
    type: 'RunAsAny',
  },
  seccompProfiles: [
    '*',
  ],
  supplementalGroups: {
    type: 'RunAsAny',
  },
  readOnlyRootFilesystem: false,
  requiredDropCapabilities: null,
};

// Define outputs below
{
  [if isOpenshift then '01_openshift-scc']: openshiftScc,
}
