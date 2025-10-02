local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.csi_exoscale;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('csi-exoscale', params.namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/csi-exoscale' % appPath]: app,
}
