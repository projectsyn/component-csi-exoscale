// main template for cm-hetznercloud
local com = import 'lib/commodore.libjsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
// The hiera parameters for the component
local params = inv.parameters.csi_exoscale;

local csiDriver = com.Kustomization(
  'https://github.com/exoscale/exoscale-csi-driver//deployment',
  params.manifestVersion,
  {
    'exoscale/csi-driver': {
      newTag: params.images.csi_driver.tag,
      newName: '%(registry)s/%(repository)s' % params.images.csi_driver,
    },
    'registry.k8s.io/sig-storage/csi-attacher': {
      newTag: params.images.csi_attacher.tag,
      newName: '%(registry)s/%(repository)s' % params.images.csi_attacher,
    },
    'registry.k8s.io/sig-storage/csi-resizer': {
      newTag: params.images.csi_resizer.tag,
      newName: '%(registry)s/%(repository)s' % params.images.csi_resizer,
    },
    'registry.k8s.io/sig-storage/csi-provisioner': {
      newTag: params.images.csi_provisioner.tag,
      newName: '%(registry)s/%(repository)s' % params.images.csi_provisioner,
    },
    'registry.k8s.io/sig-storage/csi-snapshotter': {
      newTag: params.images.csi_snapshotter.tag,
      newName: '%(registry)s/%(repository)s' % params.images.csi_snapshotter,
    },
    'registry.k8s.io/sig-storage/snapshot-controller': {
      newTag: params.images.snapshot_controller.tag,
      newName: '%(registry)s/%(repository)s' % params.images.snapshot_controller,
    },
    'registry.k8s.io/sig-storage/csi-node-driver-registrar': {
      newTag: params.images.csi_registrar.tag,
      newName: '%(registry)s/%(repository)s' % params.images.csi_registrar,
    },
    'registry.k8s.io/sig-storage/livenessprobe': {
      newTag: params.images.liveness_probe.tag,
      newName: '%(registry)s/%(repository)s' % params.images.liveness_probe,
    },
  },
  {
    patchesStrategicMerge: [
      'rm-crds.yaml',
      'rm-storageclass.yaml',
    ],
  } + com.makeMergeable(params.kustomizeInput),
) {
  'rm-crds': [ {
    '$patch': 'delete',
    apiVersion: 'apiextensions.k8s.io/v1',
    kind: 'CustomResourceDefinition',
    metadata: {
      name: 'volumesnapshotclasses.snapshot.storage.k8s.io',
    },
  }, {
    '$patch': 'delete',
    apiVersion: 'apiextensions.k8s.io/v1',
    kind: 'CustomResourceDefinition',
    metadata: {
      name: 'volumesnapshotcontents.snapshot.storage.k8s.io',
    },
  }, {
    '$patch': 'delete',
    apiVersion: 'apiextensions.k8s.io/v1',
    kind: 'CustomResourceDefinition',
    metadata: {
      name: 'volumesnapshots.snapshot.storage.k8s.io',
    },
  } ],
  'rm-storageclass': {
    '$patch': 'delete',
    apiVersion: 'storage.k8s.io/v1',
    kind: 'StorageClass',
    metadata: {
      name: 'exoscale-sbs',
    },
  },
};

csiDriver
