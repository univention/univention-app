#!/bin/bash

# @copyright Copyright (c) 2017 Arthur Schiwon <blizzz@arthur-schiwon.de>
#
# @author Arthur Schiwon <blizzz@arthur-schiwon.de>
#
# @license GNU AGPL version 3 or any later version
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

NC_PERMDATADIR="/var/lib/univention-appcenter/apps/nextcloud/data"
NC_DATADIR="$NC_PERMDATADIR/nextcloud-data"

NC_PERMCONFDIR="/var/lib/univention-appcenter/apps/nextcloud/conf"
NC_UCR_FILE="$NC_PERMCONFDIR/ucr"
NC_ADMIN_PWD_FILE="$NC_PERMCONFDIR/admin.secret"

NC_DB_TYPE="pgsql"
NC_LOCAL_ADMIN="nc_admin"
NC_LOCAL_ADMIN_PWD=`pwgen -y 30 1`
echo "$NC_LOCAL_ADMIN_PWD" > "$NC_ADMIN_PWD_FILE"
chmod 600 "$NC_ADMIN_PWD_FILE"

cd /var/www/html
if [ ! -x occ ]; then
	echo "occ missing or not executable"
	exit 1
fi

OCC="sudo -u www-data ./occ"

NC_IS_INSTALLED=`$OCC status | grep "installed: true" -c`
NC_IS_UPGRADE=1

if [ "$NC_IS_INSTALLED" -eq 0 ] ; then
    NC_IS_UPGRADE=0

    mkdir -p "$NC_DATADIR"
    chown www-data:www-data -R "$NC_DATADIR"

    $OCC maintenance:install \
        --admin-user    "$NC_LOCAL_ADMIN" \
        --admin-pass    "$NC_LOCAL_ADMIN_PWD" \
        --database      "$NC_DB_TYPE" \
        --database-host "$DB_HOST" \
        --database-port "$DB_PORT" \
        --database-name "$DB_NAME" \
        --database-user "$DB_USER" \
        --database-pass "$DB_PASSWORD" \
        --data-dir      "$NC_DATADIR"

    STATE=$?
    if [[ $STATE != 0 ]]; then
        echo  "Error while installing Nextcloud"
        exit 1;
    fi
fi

$OCC check
$OCC status
$OCC app:list
$OCC upgrade

# basic Nextcloud configuration
if [ "$NC_IS_UPGRADE" -eq 0 ] ; then
    eval "`cat \"$NC_UCR_FILE\"`"

    $OCC config:system:set trusted_domains 0 --value="$NC_UCR_DOMAIN"
    $OCC config:system:set updatechecker --value="false"    # this is handled via UCS AppCenter
    $OCC config:system:set overwriteprotocol --value="https"
    $OCC config:system:set overwritewbroot --value="/nextcloud"
    $OCC config:system:set overwrite.cli.url --value="https://$NC_UCR_DOMAIN/nextcloud"
    $OCC config:system:set htaccess.RewriteBase --value="/nextcloud"
    $OCC maintenance:update:htaccess
    $OCC config:system:set --value "\OC\Memcache\APCu" memcache.local
    echo "*/15 * * * * www-data    php -f /var/www/html/cron.php" > /etc/cron.d/nextcloud
    $OCC background:cron
    $OCC app:enable user_ldap
fi