begin;
drop table if exists shared_nodes;
create table shared_nodes (
    node_id bigint,
    way_id  text[],
    power_type char(1) array,
    path_idx float array,
    primary key (node_id)
);

insert into shared_nodes (node_id, way_id, power_type, path_idx)
    select node_id, array_agg(way_id order by way_id), 
        array_agg(power_type order by way_id), 
        array_agg(path_idx order by way_id) from (
        select id as way_id, unnest(members_nodes) as node_id,  power_type, 
            (generate_subscripts(members_nodes, 1)::float - 1.0)/(array_length(members_nodes, 1)-1) as path_idx
            from lines
            join power_type_names on power_name = power
            where array_length(members_nodes, 1) > 1 AND power is not null
    ) f group by node_id having count(*) > 1;
commit;
