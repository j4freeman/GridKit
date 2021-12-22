Documentaiton of the original GridKit can be found at the original repository, here: https://github.com/bdw/GridKit


# GridKit Modernized Fork

GridKit remains one of the most easily operated grid extraction tools for OSM data. However given its age, it now relies on tables no longer present in the default output of osm2pgsql. This fork houses a flex config lua file for osm2pgsql's new flex output functionality as well as an updated src section to integrate these changes. The entry point is now a python script rather than a shell script. All grid extraction logic is the same as in the original GridKit repo - the contents of the /src directory are almost entirely the same as the original GridKit apart from the modernization fixes.  


## Usage Info

Download a full-planet dump from
[planet.openstreetmap.org](http://planet.openstreetmap.org/pbf/) or a
geographically-bounded extract from
[geofabrik](http://download.geofabrik.de/).

Execute osm2pgsql with the flex output:
```
    osm2pgsql.exe --database <db> --username <user> -W --host <host> --output=flex --style grid_flex.lua --slim <area.osm.pbf>
```

Execute gridkit extraction:
```
    python main.py --db <db> --user <user> --host <host> --port <port>
```

The results will be written to the specified db alongside the osm export tables. Descriptions can be found in the original repo. 
