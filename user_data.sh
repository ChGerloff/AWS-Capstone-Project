#!/bin/bash
yum update -y
amazon-linux-extras install -y php8.2
yum install -y httpd mariadb-server php-mysqlnd wget unzip

systemctl enable httpd mariadb
systemctl start httpd mariadb

until mysqladmin ping >/dev/null 2>&1; do sleep 3; done

mysql -e "CREATE DATABASE wordpress;"
mysql -e "CREATE USER 'wpuser'@'localhost' IDENTIFIED BY 'StrongPass123!';"
mysql -e "GRANT ALL PRIVILEGES ON wordpress.* TO 'wpuser'@'localhost';"
mysql -e "FLUSH PRIVILEGES;"

cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/StrongPass123!/" wp-config.php

mkdir -p wp-content/decks/images
wget https://ger-op-deck-image.s3.us-west-2.amazonaws.com/above400.json -O wp-content/decks/decks.json
wget https://ger-op-deck-image.s3.us-west-2.amazonaws.com/image.zip -O /tmp/images.zip
unzip /tmp/images.zip -d wp-content/decks/images/

PLUGIN_DIR="wp-content/plugins/decklist-generator"
mkdir -p "${PLUGIN_DIR}"

cat > "${PLUGIN_DIR}/decklist-generator.php" <<'EOPHP'
<?php
/**
 * Plugin Name: Decklist Generator
 * Description: Random One Piece TCG deck generator
 * Version: 1.0
 */
if (!defined('ABSPATH')) exit;
define('DLG_DECKS_JSON', WP_CONTENT_DIR . '/decks/decks.json');
define('DLG_IMAGES_URL', content_url('decks/images'));

function dlg_load_decks() {
    if (!file_exists(DLG_DECKS_JSON)) return [];
    return json_decode(file_get_contents(DLG_DECKS_JSON), true) ?: [];
}

function dlg_shortcode($atts) {
    $atts = shortcode_atts(['leader' => ''], $atts);
    $decks = dlg_load_decks();
    if ($atts['leader']) {
        $decks = array_filter($decks, fn($d) => $d['leader_id'] === $atts['leader']);
    }
    if (empty($decks)) return '<p>No decks found.</p>';
    $deck = $decks[array_rand($decks)];

    $html = '<div class="dlg-deck"><h3>' . esc_html($deck['leader_name']) . '</h3><div class="dlg-cards">';
    foreach ($deck['cards'] as $card) {
        $img = trailingslashit(DLG_IMAGES_URL) . $card['id'] . '.png';
        $html .= '<div class="dlg-card"><img src="' . esc_url($img) . '"><div>' . esc_html($card['name']) . ' x' . $card['count'] . '</div></div>';
    }
    $html .= '</div><style>.dlg-cards{display:flex;flex-wrap:wrap;gap:10px}.dlg-card{width:150px;font-size:12px}.dlg-card img{width:100%;height:auto}</style></div>';
    return $html;
}
add_shortcode('random_deck', 'dlg_shortcode');
EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
systemctl restart httpd
