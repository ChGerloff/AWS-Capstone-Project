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
sed -i "/<?php/a define('WP_MEMORY_LIMIT', '256M');" wp-config.php

mkdir -p wp-content/decks
# Download leaders list
wget https://ger-op-decks-images.s3.eu-north-1.amazonaws.com/leaders.json -O wp-content/decks/leaders.json

PLUGIN_DIR="wp-content/plugins/decklist-generator"
mkdir -p "${PLUGIN_DIR}"

cat > "${PLUGIN_DIR}/decklist-generator.php" << 'EOPHP'
<?php
/**
 * Plugin Name: Decklist Generator
 * Description: Random One Piece TCG deck generator with leader selection
 * Version: 1.0
 */
if (!defined('ABSPATH')) exit;
define('DLG_LEADERS_JSON', WP_CONTENT_DIR . '/decks/leaders.json');
define('DLG_S3_URL', 'https://ger-op-decks-images.s3.eu-north-1.amazonaws.com');
define('DLG_IMAGES_URL', 'https://ger-op-decks-images.s3.eu-north-1.amazonaws.com');

function dlg_load_leaders() {
    if (!file_exists(DLG_LEADERS_JSON)) return array();
    $json = file_get_contents(DLG_LEADERS_JSON);
    $data = json_decode($json, true);
    return is_array($data) ? $data : array();
}

function dlg_load_decks_for_leader($leader_id) {
    $url = DLG_S3_URL . '/decks_' . $leader_id . '.json';
    $json = file_get_contents($url);
    if ($json === false) return array();
    $data = json_decode($json, true);
    return is_array($data) ? $data : array();
}

function dlg_deck_form_shortcode($atts) {
    $leaders = dlg_load_leaders();
    if (empty($leaders)) return '<p>No leaders available.</p>';
    
    $html = '<form method="get" action="">';
    $html .= '<label for="leader">Choose a Leader:</label> ';
    $html .= '<select name="leader" id="leader">';
    $html .= '<option value="">-- Select Leader --</option>';
    foreach ($leaders as $leader) {
        $selected = (isset($_GET['leader']) && $_GET['leader'] === $leader['id']) ? 'selected' : '';
        $html .= '<option value="' . esc_attr($leader['id']) . '" ' . $selected . '>' . esc_html($leader['name']) . '</option>';
    }
    $html .= '</select> ';
    $html .= '<button type="submit">Show Random Deck</button>';
    $html .= '</form>';
    
    if (isset($_GET['leader']) && !empty($_GET['leader'])) {
        $leader_id = sanitize_text_field($_GET['leader']);
        $decks = dlg_load_decks_for_leader($leader_id);
        
        if (empty($decks)) {
            $html .= '<p>No decks found for this leader.</p>';
        } else {
            $deck = $decks[array_rand($decks)];
            $leader_name = isset($deck['humanname']) ? $deck['humanname'] : 'Unknown';
            $html .= '<div class="dlg-deck"><h3>' . esc_html($leader_name) . '</h3><div class="dlg-cards">';
            
            if (isset($deck['deck']) && is_array($deck['deck'])) {
                foreach ($deck['deck'] as $card_id => $count) {
                    $img = DLG_IMAGES_URL . '/' . $card_id . '.png';
                    $html .= '<div class="dlg-card"><img src="' . esc_url($img) . '"><div>' . esc_html($card_id) . ' x' . $count . '</div></div>';
                }
            }
            
            $html .= '</div><style>.dlg-cards{display:flex;flex-wrap:wrap;gap:10px}.dlg-card{width:150px;font-size:12px}.dlg-card img{width:100%;height:auto}</style></div>';
        }
    }
    
    return $html;
}

add_shortcode('deck_selector', 'dlg_deck_form_shortcode');
EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
systemctl restart httpd
