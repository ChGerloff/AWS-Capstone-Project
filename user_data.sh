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

mkdir -p wp-content/decks
wget https://ger-op-deck-image.s3.us-west-2.amazonaws.com/above400.json -O wp-content/decks/decks.json

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
define('DLG_IMAGES_URL', 'https://ger-op-deck-image.s3.us-west-2.amazonaws.com');

function dlg_load_decks() {
    if (!file_exists(DLG_DECKS_JSON)) return array();
    $json = file_get_contents(DLG_DECKS_JSON);
    $data = json_decode($json, true);
    return is_array($data) ? $data : array();
}

function dlg_shortcode($atts) {
    $atts = shortcode_atts(array('leader' => ''), $atts);
    $decks = dlg_load_decks();
    if (!empty($atts['leader'])) {
        $filtered = array();
        foreach ($decks as $d) {
            if ($d['leader_id'] === $atts['leader']) {
                $filtered[] = $d;
            }
        }
        $decks = $filtered;
    }
    if (empty($decks)) return '<p>No decks found.</p>';
    $deck = $decks[array_rand($decks)];

    $html = '<div class="dlg-deck"><h3>' . esc_html($deck['leader_name']) . '</h3><div class="dlg-cards">';
    foreach ($deck['cards'] as $card) {
        $img = DLG_IMAGES_URL . '/' . $card['id'] . '.png';
        $html .= '<div class="dlg-card"><img src="' . esc_url($img) . '"><div>' . esc_html($card['name']) . ' x' . $card['count'] . '</div></div>';
    }
    $html .= '</div><style>.dlg-cards{display:flex;flex-wrap:wrap;gap:10px}.dlg-card{width:150px;font-size:12px}.dlg-card img{width:100%;height:auto}</style></div>';
    return $html;
}

function dlg_random_card_shortcode($atts) {
    $decks = dlg_load_decks();
    if (empty($decks)) return '<p>No cards found.</p>';
    
    $all_cards = array();
    foreach ($decks as $deck) {
        foreach ($deck['cards'] as $card) {
            $all_cards[] = $card;
        }
    }
    
    if (empty($all_cards)) return '<p>No cards found.</p>';
    $card = $all_cards[array_rand($all_cards)];
    $img = DLG_IMAGES_URL . '/' . $card['id'] . '.png';
    
    return '<div class="dlg-random-card"><img src="' . esc_url($img) . '" style="max-width:300px;height:auto;"><div><strong>' . esc_html($card['name']) . '</strong></div></div>';
}

add_shortcode('random_deck', 'dlg_shortcode');
add_shortcode('random_card', 'dlg_random_card_shortcode');
EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
systemctl restart httpd
