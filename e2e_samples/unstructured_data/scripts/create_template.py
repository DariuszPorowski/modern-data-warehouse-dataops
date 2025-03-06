# usage:
# python ./scripts/create_db_template.py --name <template-name>
# python ./scripts/create_db_template.py -n test-template-3


if __name__ == "__main__":
    import os
    import sys

    from dotenv import load_dotenv

    module_path = os.path.abspath(os.path.join("src"))
    if module_path not in sys.path:
        sys.path.append(module_path)
    load_dotenv(override=True)

    import argparse

    from common.citation_db import create_template, create_template_question_lockfile, get_conn

    parser = argparse.ArgumentParser()
    parser.add_argument("-n", "--name", required=True, help="The name of the template to create")

    args = parser.parse_args()

    conn_str = os.environ["CITATION_DB_CONNECTION_STRING"]
    print(f"Using connection string: {conn_str}")
    try:
        conn = get_conn(conn_str)
        print(f"conn: {conn}")
        cursor = conn.cursor()
        name = args.name
        template_id = create_template(conn, cursor, name)
        print(f"Created template {name} with id: {template_id}")
        print("Writing to lockfile.")
        # output_path = create_template_question_lockfile(cursor=cursor, template_id=template_id)
        # print(f"Updated template question lockfile at path {output_path}")
    finally:
        cursor.close()
        conn.close()
