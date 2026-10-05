"""Apply the fixed WSS Finder layout; app-specific identity is separate."""
import json
import sys
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

volume = Path(sys.argv[1])
layout = json.loads(Path(sys.argv[2]).read_text())
app = json.loads(Path(sys.argv[3]).read_text())
background = Alias.for_file(str(volume / '.background' / 'DMG-Background.png')).to_bytes()
with DSStore.open(str(volume / '.DS_Store'), 'w+') as store:
    store['.']['vSrn'] = ('long', 1)
    store['.']['bwsp'] = {
        'WindowBounds': '{{%d, %d}, {%d, %d}}' % (layout['windowX'], layout['windowY'], layout['width'], layout['windowHeight']),
        'ShowToolbar': False, 'ShowStatusBar': False, 'ShowPathbar': False,
        'ShowSidebar': False, 'ShowTabView': False, 'ContainerShowSidebar': False,
        'SidebarWidth': 180, 'PreviewPaneVisibility': False,
    }
    store['.']['icvp'] = {
        'viewOptionsVersion': 1, 'backgroundType': 2,
        'backgroundColorRed': 1.0, 'backgroundColorGreen': 1.0, 'backgroundColorBlue': 1.0,
        'backgroundImageAlias': background,
        'iconSize': float(layout['iconSize']), 'textSize': float(layout['labelSize']), 'labelOnBottom': True,
        'showItemInfo': False, 'showIconPreview': True,
        'arrangeBy': 'none', 'gridSpacing': 100.0,
        'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
        'scrollPositionX': 0.0, 'scrollPositionY': 0.0,
    }
    store['.']['icvl'] = ('type', b'icnv')
    store[app['appName'] + '.app']['Iloc'] = tuple(layout['appPosition'])
    store[layout['applicationsLabel']]['Iloc'] = tuple(layout['applicationsPosition'])
