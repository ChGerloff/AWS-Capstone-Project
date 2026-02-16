#!/bin/bash
exec > /var/log/user-data.log 2>&1
set -x

yum update -y

amazon-linux-extras install -y php8.2
yum install -y httpd mariadb-server php-mysqlnd wget unzip

systemctl enable httpd
systemctl start httpd

systemctl enable mariadb
systemctl start mariadb

echo "Waiting extra time for MariaDB full initialization..."
sleep 20

echo "Creating WordPress database and user..."
sudo mysql <<'EOF' 2>/var/log/mysql-userdata-error.log
CREATE DATABASE IF NOT EXISTS wordpress;
DROP USER IF EXISTS 'wpuser'@'localhost';
CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'StrongPassword123!';
ALTER USER 'wpuser'@'localhost' IDENTIFIED WITH mysql_native_password BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "Testing DB user..."
sudo mysql -e "SELECT user, host, plugin FROM mysql.user;" >> /var/log/user-data.log

cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/StrongPassword123!/" wp-config.php

mkdir -p /var/www/html/wp-content/decks/images

DECKS_ID="1gO_0gQeMOb5q7gjrAn6j6J21LY9GaGY1"
wget --no-check-certificate "https://drive.google.com/uc?export=download&id=${DECKS_ID}" -O /var/www/html/wp-content/decks/decks.json

IMAGES_ID="1uoFUYy3kceQLiuvuG7dajxT_QxFSl9ul"
wget --no-check-certificate "https://drive.google.com/uc?export=download&id=${IMAGES_ID}" -O /tmp/images.zip

unzip /tmp/images.zip -d /var/www/html/wp-content/decks/images/
rm -f /tmp/images.zip

PLUGIN_DIR="/var/www/html/wp-content/plugins/decklist-generator"
mkdir -p "${PLUGIN_DIR}"

cat > "${PLUGIN_DIR}/decklist-generator.php" <<'EOPHP'
<?php
/**
 * Plugin Name: Decklist Generator
 * Description: Random One Piece TCG deck generator by leader.
 * Version: 1.0.0
 * Author: Christoph
 */

if ( ! defined( 'ABSPATH' ) ) exit;

define( 'DLG_PLUGIN_DIR', plugin_dir_path( __FILE__ ) );
define( 'DLG_DECKS_JSON', WP_CONTENT_DIR . '/decks/decks.json' );
define( 'DLG_IMAGES_DIR_URL', content_url( 'decks/images' ) );

require_once DLG_PLUGIN_DIR . 'decklist-functions.php';

function dlg_register_shortcodes() {
    add_shortcode( 'random_deck', 'dlg_random_deck_shortcode' );
}
add_action( 'init', 'dlg_register_shortcodes' );
EOPHP

cat > "${PLUGIN_DIR}/decklist-functions.php" <<'EOPHP'
<?php

if ( ! defined( 'ABSPATH' ) ) exit;

function dlg_load_decks() {
    if ( ! file_exists( DLG_DECKS_JSON ) ) return [];
    $json = file_get_contents( DLG_DECKS_JSON );
    $data = json_decode( $json, true );
    return is_array( $data ) ? $data : [];
}

function dlg_filter_decks_by_leader( $decks, $leader_id ) {
    if ( empty( $leader_id ) ) return $decks;
    return array_values(array_filter($decks, fn($d) => $d['leader_id'] === $leader_id));
}

function dlg_pick_random_deck( $decks ) {
    return empty($decks) ? null : $decks[array_rand($decks)];
}

function dlg_render_deck_html( $deck ) {
    if ( ! $deck || empty($deck['cards']) ) return '<p>No deck data available.</p>';

    $leader_id = esc_html($deck['leader_id']);
    $leader_name = esc_html($deck['leader_name']);

    ob_start(); ?>
    <div class="dlg-deck">
        <h3><?php echo $leader_name; ?> (<?php echo $leader_id; ?>)</h3>
        <div class="dlg-cards">
            <?php foreach ( $deck['cards'] as $card ):
                $id = $card['id'];
                $name = $card['name'];
                $count = intval($card['count']);
                $img = trailingslashit(DLG_IMAGES_DIR_URL) . $id . '.png';
            ?>
            <div class="dlg-card">
                <img src="<?php echo esc_url($img); ?>" style="width:100%;height:auto;">
                <div><strong><?php echo esc_html($name); ?></strong> x<?php echo $count; ?></div>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
    <style>
        .dlg-cards { display:flex; flex-wrap:wrap; gap:10px; }
        .dlg-card { width:150px; font-size:12px; }
    </style>
    <?php return ob_get_clean();
}

function dlg_random_deck_shortcode( $atts ) {
    $atts = shortcode_atts(['leader' => ''], $atts);
    $decks = dlg_load_decks();
    $filtered = dlg_filter_decks_by_leader($decks, $atts['leader']);
    $deck = dlg_pick_random_deck($filtered);
    return dlg_render_deck_html($deck);
}
EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html

systemctl restart httpd
