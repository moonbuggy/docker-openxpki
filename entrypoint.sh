#! /bin/sh

mkdir -p /etc/openxpki/config.d/system/

SQL_IP="$(dig +short "${OXI_TEST_DB_MYSQL_DBHOST}")"

# set database.yaml from env
DB_YAML="/etc/openxpki/config.d/system/database.yaml"

printf '%s.. ' "${DB_YAML}"
for var_name in DBHOST DBPORT NAME USER PASSWORD; do
	var="OXI_TEST_DB_MYSQL_${var_name}"
	eval "val=\$${var}"

	[ -z "${val}" ] && continue

	yaml_value="${val}"

	case "${var_name}" in
		DBHOST) yaml_name='host' && yaml_value="${SQL_IP}" ;;
		DBPORT) yaml_name='port' ;;
		PASSWORD) yaml_name='passwd' ;;
		*) yaml_name="${var_name}" ;;
	esac

	sed -E "s|(^\s+${yaml_name:-${var_name}}:\s+).*$|\\1${yaml_value:-${val}}|gmi" -i "${DB_YAML}"
done && echo 'OK'

# fix some tests
TEST_DIR='/build/openxpki/core/server/t/31_database'

for file in '24-transactions-isolation.t' '25-autocommit.t'; do
	printf '%s/%s.. ' "${TEST_DIR}" "${file}"
	echo "SQL IP: ${SQL_IP}"
	sed -E "s|(^\s+host\s+=>\s+).*$|\\1'${SQL_IP:-${OXI_TEST_DB_MYSQL_DBHOST}}',|gmi" -i "${TEST_DIR}/${file}"

	echo OK
done

(exec "$@")

# keep running indefinitely
tail -f /dev/null
