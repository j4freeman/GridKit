import argparse
from getpass import getpass
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from time import sleep
import logging

logging.root.setLevel(logging.INFO)

def parse_args():
    """ "method wrapping command line arg parsing"""
    parser = argparse.ArgumentParser(description='Command arg parsing for gridkit')

    parser.add_argument('--db', type=str, nargs=1, required=True, help='DB name')
    parser.add_argument('--host', type=str, nargs=1, required=True, help='DB host location')
    parser.add_argument('--user', type=str, nargs=1, required=True, help='DB username')
    parser.add_argument('--port', type=int, nargs=1, required=True, help='DB port')

    args = parser.parse_args()

    args = vars(args)

    return {k: v[0] for k, v in args.items()}


args = parse_args()
password = getpass()

engine = create_engine(
        "postgresql://"
        f"{args['user']}:"
        f"{password}@"
        f"{args['host']}:"
        f"{args['port']}/"
        f"{args['db']}"
    )

session = sessionmaker(engine, autocommit=False)
conn = session()

logging.info("Preparing Tables")
conn.execute(open("src/prepare-tables.sql", "r").read())

# # shared node algorithms before any others
logging.info("Executing node-1-find-shared.sql")
conn.execute(open("src/node-1-find-shared.sql", "r").read())
logging.info("Executing node-2-merge-lines.sql")
conn.execute(open("src/node-2-merge-lines.sql", "r").read())
logging.info("Executing node-3-line-joints.sql")
conn.execute(open("src/node-3-line-joints.sql", "r").read())

sleep(5)

# # spatial algorithms benefit from reduction of work from shared node algorithms
logging.info("Executing spatial-1-merge-stations.sql")
conn.execute(open("src/spatial-1-merge-stations.sql", "r").read())
logging.info("Executing spatial-2-eliminate-internal-lines.sql")
conn.execute(open("src/spatial-2-eliminate-internal-lines.sql", "r").read())
logging.info("Executing spatial-3-eliminate-line-overlap.sql")
conn.execute(open("src/spatial-3-eliminate-line-overlap.sql", "r").read())
logging.info("Executing spatial-4-attachment-joints.sql")
conn.execute(open("src/spatial-4-attachment-joints.sql", "r").read())
logging.info("Executing spatial-5a-line-terminal-intersections.sql")
conn.execute(open("src/spatial-5a-line-terminal-intersections.sql", "r").read())
logging.info("Executing spatial-5b-mutual-terminal-intersections.sql")
conn.execute(open("src/spatial-5b-mutual-terminal-intersections.sql", "r").read())
logging.info("Executing spatial-5c-joint-stations.sql")
conn.execute(open("src/spatial-5c-joint-stations.sql", "r").read())
logging.info("Executing spatial-6-merge-lines.sql")
conn.execute(open("src/spatial-6-merge-lines.sql", "r").read())

sleep(5)

# # topological algorithms
logging.info("Executing topology-1-connections.sql")
conn.execute(open("src/topology-1-connections.sql", "r").read())
logging.info("Executing topology-2a-dangling-joints.sql")
conn.execute(open("src/topology-2a-dangling-joints.sql", "r").read())
logging.info("Executing topology-2b-redundant-splits.sql")
conn.execute(open("src/topology-2b-redundant-splits.sql", "r").read())
logging.info("Executing topology-2c-redundant-joints.sql")
conn.execute(open("src/topology-2c-redundant-joints.sql", "r").read())
logging.info("Executing topology-3a-assign-tags.sql")
conn.execute(open("src/topology-3a-assign-tags.sql", "r").read())
logging.info("Executing topology-3b-electrical-properties.sql")
conn.execute(open("src/topology-3b-electrical-properties.sql", "r").read())
logging.info("Executing topology-4-high-voltage-network.sql")
conn.execute(open("src/topology-4-high-voltage-network.sql", "r").read())
logging.info("Executing topology-5-abstraction.sql")
conn.execute(open("src/topology-5-abstraction.sql", "r").read())

logging.info("Committing Results")
conn.flush()
conn.commit()
conn.close()