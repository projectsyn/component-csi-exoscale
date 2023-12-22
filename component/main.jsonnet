// main template for csi-exoscale
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local sc = import 'lib/storageclass.libsonnet';

// The hiera parameters for the component
local params = inv.parameters.csi_exoscale;
local isOpenshift = std.startsWith(inv.parameters.facts.distribution, 'openshift');

local namespace = kube.Namespace(params.namespace) {
  metadata+: {
    labels+: {
      'app.kubernetes.io/name': params.namespace,
      'pod-security.kubernetes.io/enforce': 'privileged',
      // Configure the namespaces so that the OCP4 cluster-monitoring
      // Prometheus can find the servicemonitors and rules.
      [if isOpenshift then 'openshift.io/cluster-monitoring']: 'true',
    },
  },
};


// RBAC

local saNode = kube.ServiceAccount('exoscale-csi-node') {
  metadata+: {
    namespace: params.namespace,
  },
};

local saController = kube.ServiceAccount('exoscale-csi-controller') {
  metadata+: {
    namespace: params.namespace,
  },
};


local clusterRoleNode = kube.ClusterRole('exoscale-csi-node-driver-registrar') {
  rules: [
    { apiGroups: [ '' ], resources: [ 'events', 'pods', 'nodes' ], verbs: [ 'get', 'list', 'watch', 'create', 'update', 'patch' ] },
  ],
};

local clusterBindingNode = kube.ClusterRoleBinding('exoscale-csi-node-driver-registrar') {
  subjects_: [ saNode ],
  roleRef_: clusterRoleNode,
};


local clusterRoleController = kube.ClusterRole('exoscale-csi-controller') {
  rules: [
    { apiGroups: [ '' ], resources: [ 'secrets', 'events', 'nodes', 'pods', 'persistentvolumes', 'persistentvolumeclaims' ], verbs: [ '*' ] },
    { apiGroups: [ 'storage.k8s.io' ], resources: [ 'storageclasses', 'csinodes', 'volumeattachments' ], verbs: [ '*' ] },
    { apiGroups: [ 'snapshot.storage.k8s.io' ], resources: [ 'volumesnapshots', 'volumesnapshots/status', 'volumesnapshotclasses', 'volumesnapshotcontents', 'volumesnapshotcontents/status' ], verbs: [ '*' ] },
    { apiGroups: [ 'coordination.k8s.io' ], resources: [ 'leases' ], verbs: [ '*' ] },
  ],
};

local clusterBindingController = kube.ClusterRoleBinding('exoscale-csi-controller') {
  subjects_: [ saController ],
  roleRef_: clusterRoleController,
};


local clusterRoleAttacher = kube.ClusterRole('exoscale-csi-attacher') {
  rules: [
    { apiGroups: [ '' ], resources: [ 'nodes', 'persistentvolumes' ], verbs: [ '*' ] },
    { apiGroups: [ 'storage.k8s.io' ], resources: [ 'csinodes', 'volumeattachments', 'volumeattachments/status' ], verbs: [ '*' ] },
  ],
};

local clusterBindingAttacher = kube.ClusterRoleBinding('exoscale-csi-attacher') {
  subjects_: [ saController ],
  roleRef_: clusterRoleAttacher,
};


local clusterRoleSnapshotter = kube.ClusterRole('exoscale-csi-snapshotter') {
  rules: [
    { apiGroups: [ '' ], resources: [ 'secrets', 'events', 'persistentvolumes', 'persistentvolumeclaims' ], verbs: [ '*' ] },
    { apiGroups: [ 'storage.k8s.io' ], resources: [ 'storageclasses' ], verbs: [ '*' ] },
    { apiGroups: [ 'snapshot.storage.k8s.io' ], resources: [ 'volumeattachments', 'volumeattachments/status', 'volumesnapshotclasses', 'volumesnapshotcontents' ], verbs: [ '*' ] },
    { apiGroups: [ 'apiextensions.k8s.io' ], resources: [ 'customresourcedefinitions', 'leases' ], verbs: [ '*' ] },
  ],
};

local clusterBindingSnapshotter = kube.ClusterRoleBinding('exoscale-csi-snapshotter') {
  subjects_: [ saController ],
  roleRef_: clusterRoleSnapshotter,
};


local clusterRoleResizer = kube.ClusterRole('exoscale-csi-external-resizer') {
  rules: [
    { apiGroups: [ '' ], resources: [ 'pods', 'events', 'persistentvolumes', 'persistentvolumeclaims', 'persistentvolumeclaims/status' ], verbs: [ '*' ] },
  ],
};

local clusterBindingResizer = kube.ClusterRoleBinding('exoscale-csi-external-resizer') {
  subjects_: [ saController ],
  roleRef_: clusterRoleResizer,
};


// CSI Driver

local csiDriver = kube._Object('storage.k8s.io/v1', 'CSIDriver', 'csi.exoscale.com') {
  spec: {
    attachRequired: true,
    podInfoOnMount: true,
  },
};

local volumeSnapshotClass = kube._Object('snapshot.storage.k8s.io/v1', 'VolumeSnapshotClass', 'exoscale-snapshot') {
  spec: {
    driver: 'csi.exoscale.com',
    deletionPolicy: 'Delete',
  },
};

local storageClass = sc.storageClass('exoscale-block-storage') {
  allowVolumeExpansion: true,
  provisioner: 'csi.exoscale.com',
  volumeBindingMode: 'WaitForFirstConsumer',
};


// API Secret

local apiCredentials = kube.Secret('exoscale-csi-credentials') {
  metadata+: {
    namespace: params.namespace,
  },
  stringData: {
    EXOSCALE_API_KEY: params.apiSecret.accessKey,
    EXOSCALE_API_SECRET: params.apiSecret.secretKey,
  },
};


// Deployments

local exoscaleContainer(mode) = kube.Container('exoscale-csi-plugin') {
  image: '%(registry)s/%(repository)s:%(tag)s' % params.images.csi_driver,
  imagePullPolicy: 'Always',
  args_:: {
    v: '4',
    endpoint: '$(CSI_ENDPOINT)',
    mode: mode,
  },
  env_:: {
    CSI_ENDPOINT: 'unix:///var/lib/csi/sockets/pluginproxy/csi.sock',
    POD_NAME: { fieldRef: { fieldPath: 'metadata.name' } },
    POD_NAMESPACE: { fieldRef: { fieldPath: 'metadata.namespace' } },
  },
  ports_:: {
    healthz: {
      containerPort: '9808',
      protocol: 'TCP',
    },
  },
  resources: std.get(params.resources, mode, {}),
  livenessProbe: {
    httpGet: {
      path: '/healthz',
      port: 'healthz',
    },
    initialDelaySeconds: 10,
    timeoutSeconds: 3,
    periodSeconds: 2,
    failureThreshold: 5,
  },
};

local csiContainer(name, image) = kube.Container(name) {
  image: '%(registry)s/%(repository)s:%(tag)s' % image,
  args: [
    '--v=5',
    '--leader-election',
    '--csi-address=$(CSI_ADDRESS)',
  ],
  env_:: {
    CSI_ADDRESS: '/var/lib/csi/sockets/pluginproxy/csi.sock',
  },
  volumeMounts_:: {
    'socket-dir': { mountPath: '/var/lib/csi/sockets/pluginproxy/' },
  },
};

local dsName = saNode.metadata.name;
local daemonset = kube.DaemonSet(dsName) {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    selector: { matchLabels: { app: dsName } },
    template+: {
      spec+: {
        dnsPolicy: 'Default',
        priorityClassName: 'system-node-critical',
        serviceAccount: saNode.metadata.name,
        nodeSelector: { 'kubernetes.io/os': 'linux' },
        hostNetwork: true,
        containers_:: {
          default: exoscaleContainer('node') {
            securityContext: { privileged: true },
            volumeMounts_:: {
              'plugin-dir': { mountPath: '/csi' },
              'kubelet-dir': { mountPath: '/var/lib/kubelet', mountPropagation: 'Bidirectional' },
              'device-dir': { mountPath: '/dev' },
            },
          },
          csi_registrar: kube.Container('csi-registrar') {
            image: '%(registry)s/%(repository)s:%(tag)s' % params.images.csi_registrar,
            args_:: {
              v: '2',
              'csi-address': '$(CSI_ADDRESS)',
              'kubelet-registration-path': '$(KUBELET_REGISTRATION_PATH)',
            },
            env_:: {
              CSI_ADDRESS: '/csi/csi.sock',
              KUBELET_REGISTRATION_PATH: '/var/lib/kubelet/plugins/csi.exoscale.com/csi.sock',
              KUBE_NODE_NAME: { fieldRef: { fieldPath: 'spec.nodeName' } },
            },
            volumeMounts_:: {
              'plugin-dir': { mountPath: '/csi' },
              'registration-dir': { mountPath: '/registration' },
            },
          },
          liveness_probe: csiContainer('liveness-probe', params.images.liveness_probe) {
            args: [ '--csi-address=$(CSI_ADDRESS)' ],
            env_:: {
              CSI_ADDRESS: '/csi/csi.sock',
            },
            volumeMounts_:: {
              'plugin-dir': { mountPath: '/csi' },
            },
          },
        },
        volumes_:: {
          'registration-dir': { hostPath: { path: '/var/lib/kubelet/plugins_registry/', type: 'DirectoryOrCreate' } },
          'plugin-dir': { hostPath: { path: '/var/lib/kubelet/plugins/csi.exoscale.com', type: 'DirectoryOrCreate' } },
          'kubelet-dir': { hostPath: { path: '/var/lib/kubelet', type: 'Directory' } },
          'device-dir': { hostPath: { path: '/dev' } },
        },
      },
    },
  },
};


// Deployment

local deployName = saController.metadata.name;
local deployment = kube.Deployment(deployName) {
  metadata+: {
    namespace: params.namespace,
  },
  spec+: {
    selector: { matchLabels: { app: deployName } },
    replicas: 1,
    template+: {
      spec+: {
        dnsPolicy: 'Default',
        priorityClassName: 'system-cluster-critical',
        serviceAccount: saController.metadata.name,
        containers_:: {
          default: exoscaleContainer('controller') {
            envFrom: { secretRef: { name: apiCredentials.metadata.name } },
            volumeMounts_:: {
              'socket-dir': { mountPath: '/var/lib/csi/sockets/pluginproxy/' },
            },
          },
          csi_attacher: csiContainer('csi-attacher', params.images.csi_attacher) {
            args+: [
              '--default-fstype=ext4',
              '--feature-gates=Topology=true',
            ],
          },
          csi_resizer: csiContainer('csi-resizer', params.images.csi_resizer),
          csi_provisioner: csiContainer('csi-provisioner', params.images.csi_provisioner),
          csi_snapshotter: csiContainer('csi-snapshotter', params.images.csi_snapshotter) {
            args: [
              '--v=5',
              '--leader-election',
            ],
            env: [],
            volumeMounts: [],
          },
          snapshot_controller: csiContainer('snapshot-controller', params.images.snapshot_controller),
          liveness_probe: csiContainer('liveness-probe', params.images.liveness_probe) {
            args: [ '--csi-address=$(CSI_ADDRESS)' ],
          },
        },
        volumes_:: {
          'socket-dir': { emptyDir: {} },
        },
      },
    },
  },
};

// Define outputs below
{
  '00_namespace': namespace,
  '10_rbac_daemonset': [
    saNode,
    clusterRoleNode,
  ],
  '10_rbac_deployment': [
    saController,
    clusterBindingNode,
    clusterRoleController,
    clusterBindingController,
    clusterRoleAttacher,
    clusterBindingAttacher,
    clusterRoleSnapshotter,
    clusterBindingSnapshotter,
    clusterRoleResizer,
    clusterBindingResizer,
  ],
  '20_csi_driver': csiDriver,
  '20_snapshot_class': volumeSnapshotClass,
  '20_storage_class': storageClass,
  '30_secret': apiCredentials,
  '30_daemonset': daemonset,
  '30_deployment': deployment,
}
