import { PanelPlugin } from '@grafana/data';
import { MissionControlPanel } from './MissionControlPanel';

export const plugin =
  new PanelPlugin(MissionControlPanel);
