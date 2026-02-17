#!/bin/bash
exec > /var/log/user-data-basic.log 2>&1
set -eux

# Minimal user-data to install WordPress and fetch decks + images from public S3

yum update -y

amazon-linux-extras install -y php8.2
yum install -y httpd mariadb-server php-mysqlnd wget unzip

systemctl enable --now httpd
systemctl enable --now mariadb

echo "Waiting for MariaDB..."
for i in {1..20}; do
  if mysql -e "SELECT 1" >/dev/null 2>&1; then
    echo "mariadb ready"; break
  fi
  sleep 2
done

# Create DB and user
mysql <<'SQL'
CREATE DATABASE IF NOT EXISTS wordpress;
CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
SQL

cd /var/www/html
wget -q https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/StrongPassword123!/" wp-config.php

mkdir -p /var/www/html/wp-content/decks/images

# Download deck JSON and images.zip from public S3 URLs
DECKS_URL="https://ger-op-deck-image.s3.us-west-2.amazonaws.com/above400.json"
IMAGES_URL="https://ger-op-deck-image.s3.us-west-2.amazonaws.com/image.zip"

curl -sfL "${DECKS_URL}" -o /var/www/html/wp-content/decks/decks.json || echo "failed downloading decks"
curl -sfL "${IMAGES_URL}" -o /tmp/image.zip || echo "failed downloading images zip"

if [ -f /tmp/image.zip ]; then
  unzip -o /tmp/image.zip -d /var/www/html/wp-content/decks/images/ || echo "unzip failed"
fi

# Minimal plugin files (same structure as your plugin)
PLUGIN_DIR="/var/www/html/wp-content/plugins/decklist-generator"
mkdir -p "${PLUGIN_DIR}"

cat > "${PLUGIN_DIR}/decklist-generator.php" <<'EOPHP'
<?php
/**
 * Plugin Name: Decklist Generator
 */
if ( ! defined( 'ABSPATH' ) ) exit;
define( 'DLG_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
define( 'DLG_DECKS_JSON', WP_CONTENT_DIR . '/decks/decks.json' );
define( 'DLG_IMAGES_DIR_URL', content_url( 'decks/images' ) );
require_once DLG_PLUGIN_DIR . 'decklist-functions.php';
function dlg_register_shortcodes() { add_shortcode( 'random_deck', 'dlg_random_deck_shortcode' ); }
add_action( 'init', 'dlg_register_shortcodes' );
EOPHP

cat > "${PLUGIN_DIR}/decklist-functions.php" <<'EOPHP'
<?php
if ( ! defined( 'ABSPATH' ) ) exit;
function dlg_load_decks() {
  if ( ! file_exists( DLG_DECKS_JSON ) ) return [];
  $data = json_decode( file_get_contents( DLG_DECKS_JSON ), true );
  return is_array($data) ? $data : [];
}
function dlg_pick_random_deck( $decks ) { return empty($decks) ? null : $decks[array_rand($decks)]; }
function dlg_render_deck_html( $deck ) {
  if ( ! $deck ) return '<p>No deck data.</p>';
  $out = "<div><h3>".esc_html($deck['leader_name'])."</h3><ul>";
  foreach($deck['cards'] as $c) { $img = trailingslashit(DLG_IMAGES_DIR_URL).$c['id'].'.png'; $out .= "<li><img src='".esc_url($img)."' style='width:60px'> " . esc_html($c['name']) . " x".intval($c['count'])."</li>"; }
  $out .= "</ul></div>"; return $out;
}
function dlg_random_deck_shortcode( $atts ) { $decks = dlg_load_decks(); $d = dlg_pick_random_deck($decks); return dlg_render_deck_html($d); }
EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

systemctl restart httpd || true

echo "user-data-basic finished"
