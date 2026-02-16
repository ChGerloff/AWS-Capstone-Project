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

echo "Waiting for MariaDB to be fully ready..."
for i in {1..30}; do
  if sudo mysql -e "SELECT 1" >/dev/null 2>&1; then
    echo "MariaDB is ready"
    break
  fi
  echo "Waiting for MariaDB... attempt $i/30"
  sleep 2
done

echo "Creating WordPress database and user..."
sudo mysql <<'EOF' >>/var/log/user-data.log 2>&1
CREATE DATABASE IF NOT EXISTS wordpress;
DROP USER IF EXISTS 'wpuser'@'localhost';
DROP USER IF EXISTS 'wpuser'@'%';
CREATE USER IF NOT EXISTS 'wpuser'@'localhost' IDENTIFIED BY 'StrongPassword123!';
CREATE USER IF NOT EXISTS 'wpuser'@'%' IDENTIFIED BY 'StrongPassword123!';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'%';
FLUSH PRIVILEGES;
EOF

echo "Testing DB user (socket localhost)..." >> /var/log/user-data.log
sudo mysql -u wpuser -p'StrongPassword123!' -h localhost wordpress -e "SELECT 1;" >> /var/log/user-data.log 2>&1
if [ $? -eq 0 ]; then
  echo "Database connection successful (localhost)" >> /var/log/user-data.log
else
  echo "ERROR: Database connection failed (localhost)" >> /var/log/user-data.log
fi

echo "Testing DB user (127.0.0.1 TCP)..." >> /var/log/user-data.log
sudo mysql -u wpuser -p'StrongPassword123!' -h 127.0.0.1 wordpress -e "SELECT 1;" >> /var/log/user-data.log 2>&1
if [ $? -eq 0 ]; then
  echo "Database connection successful (127.0.0.1)" >> /var/log/user-data.log
else
  echo "ERROR: Database connection failed (127.0.0.1)" >> /var/log/user-data.log
fi

cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

cp wp-config-sample.php wp-config.php

# Replace the common placeholder tokens in the sample config
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/StrongPassword123!/" wp-config.php

echo "WordPress configuration updated" >> /var/log/user-data.log

mkdir -p /var/www/html/wp-content/decks/images

DECKS_ID="1gO_0gQeMOb5q7gjrAn6j6J21LY9GaGY1"
wget --no-check-certificate "https://drive.google.com/uc?export=download&id=${DECKS_ID}" -O /var/www/html/wp-content/decks/decks.json

IMAGES_ID="1uoFUYy3kceQLiuvuG7dajxT_QxFSl9ul"
# Robust Google Drive download: fetch page, extract confirm token if present, then download
curl -s -L -c /tmp/gcookie "https://drive.google.com/uc?export=download&id=${IMAGES_ID}" -o /tmp/gdpage

CONFIRM_TOKEN=$(grep -oE 'confirm=[0-9A-Za-z_-]+' /tmp/gdpage | head -n1 | sed 's/confirm=//; s/&amp.*//')
if [ -n "${CONFIRM_TOKEN}" ]; then
  curl -s -L -b /tmp/gcookie "https://drive.google.com/uc?export=download&confirm=${CONFIRM_TOKEN}&id=${IMAGES_ID}" -o /tmp/images.zip
else
  # Try direct download (may be small file or public)
  curl -s -L -b /tmp/gcookie "https://drive.google.com/uc?export=download&id=${IMAGES_ID}" -o /tmp/images.zip
fi

# Validate zip before extracting
if [ -f /tmp/images.zip ]; then
  if unzip -t /tmp/images.zip >/dev/null 2>&1; then
    unzip /tmp/images.zip -d /var/www/html/wp-content/decks/images/
    echo "Images extracted successfully" >> /var/log/user-data.log
  else
    echo "WARNING: images.zip is not a valid zip file. Saving preview to /tmp/images.zip.html" >> /var/log/user-data.log
    cp /tmp/images.zip /tmp/images.zip.html
    file /tmp/images.zip >> /var/log/user-data.log
    head -n 200 /tmp/images.zip.html >> /var/log/user-data.log
  fi
else
  echo "WARNING: images.zip not downloaded" >> /var/log/user-data.log
fi

rm -f /tmp/images.zip /tmp/gcookie /tmp/gdpage

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
