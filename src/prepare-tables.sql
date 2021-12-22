/* assume we use the osm2pgsql 'accidental' tables */
begin transaction;

drop table if exists node_geometry;
drop table if exists way_geometry;
drop table if exists relation_member;
drop table if exists power_type_names;
drop table if exists electrical_properties;
drop table if exists power_station;
drop table if exists power_line;
drop table if exists osm_tags;
drop table if exists osm_objects;

drop sequence if exists synthetic_objects;
/* functions */
drop function if exists buffered_terminals(geometry(linestring));
drop function if exists buffered_station_point(geometry(point));
drop function if exists buffered_station_area(geometry(polygon));
drop function if exists source_objects(text array);
drop function if exists connect_lines(a geometry(linestring), b geometry(linestring));
drop function if exists connect_lines_terminals(geometry, geometry);
drop function if exists reuse_terminal(geometry, geometry, geometry);
drop function if exists minimal_terminals(geometry, geometry, geometry);
drop function if exists array_replace(anyarray, anyarray, anyarray);
drop function if exists array_remove(anyarray, anyarray);
drop function if exists array_sym_diff(anyarray, anyarray);
drop function if exists array_merge(anyarray, anyarray);

-- todo, split function preparation from this file
create function array_remove(a anyarray, b anyarray) returns anyarray as $$
begin
    return array((select unnest(a) except select unnest(b)));
end;
$$ language plpgsql;

create function array_replace(a anyarray, b anyarray, n anyarray) returns anyarray as $$
begin
    return array((select unnest(a) except select unnest(b) union select unnest(n)));
end;
$$ language plpgsql;

create function array_sym_diff(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(((select unnest(a) union select unnest(b))
                   except
                  (select unnest(a) intersect select unnest(b))));
end;
$$ language plpgsql;

create function array_merge(a anyarray, b anyarray) returns anyarray as $$
begin
    return array(select unnest(a) union select unnest(b));
end;
$$ language plpgsql;


create function buffered_terminals(line geometry(linestring)) returns geometry(linestring) as $$
begin
    return st_buffer(st_union(st_startpoint(line), st_endpoint(line)), least(50.0, st_length(line)/3.0));
end
$$ language plpgsql;

create function buffered_station_point(point geometry(point)) returns geometry(polygon) as $$
begin
    return st_buffer(point, 50);
end;
$$ language plpgsql;

create function buffered_station_area(area geometry(polygon)) returns geometry(polygon) as $$
begin
    return st_convexhull(st_buffer(area, least(sqrt(st_area(area)), 100)));
end;
$$ language plpgsql;

create function source_objects (ref text array) returns text array as $$
begin
    return array((select distinct unnest(objects) from osm_objects where osm_id = any(ref)));
end;
$$ language plpgsql;


create function connect_lines (a geometry(linestring), b geometry(linestring)) returns geometry(linestring) as $$
begin
    -- select the shortest line that comes from joining the lines
     -- in all possible directions
    return (select e from (
                select unnest(
                         array[st_makeline(a, b),
                               st_makeline(a, st_reverse(b)),
                               st_makeline(st_reverse(a), b),
                               st_makeline(st_reverse(a), st_reverse(b))]) e) f
                order by st_length(e) limit 1);
end;
$$ language plpgsql;

create function connect_lines_terminals(a geometry(multipolygon), b geometry(multipolygon))
    returns geometry(multipolygon) as $$
begin
    return case when st_intersects(st_geometryn(a, 1), st_geometryn(b, 1)) then st_union(st_geometryn(a, 2), st_geometryn(b, 2))
                when st_intersects(st_geometryn(a, 2), st_geometryn(b, 1)) then st_union(st_geometryn(a, 1), st_geometryn(b, 2))
                when st_intersects(st_geometryn(a, 1), st_geometryn(b, 2)) then st_union(st_geometryn(a, 2), st_geometryn(b, 1))
                                                                           else st_union(st_geometryn(a, 1), st_geometryn(b, 1)) end;
end;
$$ language plpgsql;



create function reuse_terminal(point geometry, terminals geometry, line geometry) returns geometry as $$
declare
    max_buffer float;
begin
    max_buffer = least(st_length(line) / 3.0, 50.0);
    if st_geometrytype(terminals) = 'ST_MultiPolygon' then
        if st_distance(st_geometryn(terminals, 1), point) < 1 then
            return st_geometryn(terminals, 1);
        elsif st_distance(st_geometryn(terminals, 2), point) < 1 then
            return st_geometryn(terminals, 2);
        else
            return st_buffer(point, max_buffer);
        end if;
    else
        return st_buffer(point, max_buffer);
    end if;
end;
$$ language plpgsql;

create function minimal_terminals(line geometry, area geometry, terminals geometry) returns geometry as $$
declare
    start_term geometry;
    end_term   geometry;
begin
    start_term = case when st_distance(st_startpoint(line), area) < 1 then st_buffer(st_startpoint(line), 1)
                      else reuse_terminal(st_startpoint(line), terminals, line) end;
    end_term   = case when st_distance(st_endpoint(line), area) < 1 then st_buffer(st_endpoint(line), 1)
                      else reuse_terminal(st_endpoint(line), terminals, line) end;
    return st_union(start_term, end_term);
end;
$$ language plpgsql;


create table osm_tags (
    osm_id text, -- todo use system id for this
    tags   jsonb,
    primary key (osm_id)
);

create table osm_objects (
    osm_id text,
    objects text array,
    primary key (osm_id)
);

/* lookup table for power types */
create table power_type_names (
    power_name text primary key,
    power_type text not null,
    check (power_type in ('s','l','r', 'v'))
);

create table electrical_properties (
    osm_id text,
    frequency float array,
    voltage int array,
    conductor_bundles int array,
    subconductors int array,
    power_name text,
    operator text,
    name text
);

create table power_station (
    osm_id text,
    power_name text not null,
    location geometry(point, 3857),
    area geometry(polygon, 3857),
    primary key (osm_id)
);

create table power_line (
    osm_id text,
    power_name text not null,
    extent    geometry(linestring, 3857),
    terminals geometry(geometry, 3857),
    primary key (osm_id)
);




/* all things recognised as certain stations */
insert into power_type_names (power_name, power_type)
    values ('station', 's'),
           ('substation', 's'),
           ('sub_station', 's'),
           ('plant', 's'),
           ('cable', 'l'),
           ('line', 'l'),
           ('minor_cable', 'l'),
           ('minor_line', 'l'),
           -- virtual elements
           ('merge', 'v'),
           ('joint', 'v');


-- osm_id, station name, centroid, polygon
INSERT INTO power_station (osm_id, power_name, location, area)
    SELECT concat('polygon', id), power, ST_Centroid(geom), buffered_station_area(geom) FROM polygons WHERE power IN (
        SELECT power_name FROM power_type_names WHERE power_type = 's'
    );

insert into power_station (osm_id, power_name, location, area)
    select concat('node', n.id), power, geom, buffered_station_point(geom)
        from points n
        where power in (
             select power_name from power_type_names where power_type = 's'
        );

-- insert into power_station (osm_id, power_name, location, area)
--     select concat('lineg', n.id), power, ST_Centroid(geom), st_buffer(geom, least(100, st_length(geom)/2))
--     -- select n.id, power, ST_Centroid(geom), st_buffer(geom, least(100, st_length(geom)/2))
--         from lines n
--         where power in (
--              select power_name from power_type_names where power_type = 's'
        -- );

insert into power_line (osm_id, power_name, extent, terminals)
    -- select concat('lineg', id), power, geom, buffered_terminals(geom)
    select id, power, geom, buffered_terminals(geom)
        from lines w
        where power in (
            select power_name from power_type_names where power_type = 'l'
        );

-- initialize osm objects table
insert into osm_objects (osm_id, objects)
    select osm_id, array[osm_id] from power_line;

insert into osm_objects (osm_id, objects)
    select osm_id, array[osm_id] from power_station;

-- initialize osm tags table
insert into osm_tags (osm_id, tags)
    select concat('node', id), tags from points where power is not null;
insert into osm_tags (osm_id, tags)
    -- select concat('lineg', id), tags from lines where power is not null;
    select id, tags from lines where power is not null;
insert into osm_tags (osm_id, tags)
    select concat('polygon', id), tags from polygons where power is not null;
    -- select id, tags from polygons where power is not null;


create index power_station_area   on power_station using gist(area);
create index power_line_extent    on power_line    using gist(extent);
create index power_line_terminals on power_line    using gist(terminals);
create index osm_objects_objects  on osm_objects   using gin(objects);
create sequence synthetic_objects start 1;

commit;
