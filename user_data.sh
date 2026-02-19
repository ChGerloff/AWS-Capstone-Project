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

function dlg_leader_gallery_shortcode($atts) {
    $leaders = dlg_load_leaders();
    if (empty($leaders)) return '<p>No leaders available.</p>';
    
    $html = '<div class="dlg-leader-gallery">';
    foreach ($leaders as $leader) {
        $img = DLG_IMAGES_URL . '/' . $leader['id'] . '.png';
        $url = add_query_arg('leader', $leader['id']);
        $html .= '<div class="dlg-leader-card">';
        $html .= '<a href="' . esc_url($url) . '">';
        $html .= '<img src="' . esc_url($img) . '" alt="' . esc_attr($leader['name']) . '">';
        $html .= '<div class="dlg-leader-name">' . esc_html($leader['name']) . '</div>';
        $html .= '</a></div>';
    }
    $html .= '</div>';
    $html .= '<style>';
    $html .= '.dlg-leader-gallery{display:flex;flex-wrap:wrap;gap:15px;margin:20px 0}';
    $html .= '.dlg-leader-card{width:200px;text-align:center;border:2px solid #ddd;border-radius:8px;padding:10px;transition:transform 0.2s}';
    $html .= '.dlg-leader-card:hover{transform:scale(1.05);border-color:#333}';
    $html .= '.dlg-leader-card img{width:100%;height:auto;border-radius:5px}';
    $html .= '.dlg-leader-name{margin-top:10px;font-weight:bold;font-size:14px}';
    $html .= '</style>';
    
    return $html;
}

function dlg_deck_viewer_shortcode($atts) {
    if (!isset($_GET['leader']) || empty($_GET['leader'])) {
        return '<p>Please select a leader from the gallery.</p>';
    }
    
    $leader_id = sanitize_text_field($_GET['leader']);
    $decks = dlg_load_decks_for_leader($leader_id);
    
    if (empty($decks)) {
        return '<p>No decks found for this leader.</p>';
    }
    
    $leader_name = isset($decks[0]['humanname']) ? $decks[0]['humanname'] : 'Unknown';
    
    // Calculate card statistics
    $card_counts = array();
    foreach ($decks as $deck) {
        if (isset($deck['deck']) && is_array($deck['deck'])) {
            foreach ($deck['deck'] as $card_id => $count) {
                if (!isset($card_counts[$card_id])) {
                    $card_counts[$card_id] = 0;
                }
                $card_counts[$card_id]++;
            }
        }
    }
    arsort($card_counts);
    $top_cards = array_slice($card_counts, 0, 10, true);
    
    // Display statistics
    $html = '<div class="dlg-stats">';
    $html .= '<h2>' . esc_html($leader_name) . '</h2>';
    $html .= '<p>Total Decks: ' . count($decks) . '</p>';
    $html .= '<h3>Most Played Cards</h3>';
    $html .= '<div class="dlg-top-cards">';
    foreach ($top_cards as $card_id => $appearances) {
        $img = DLG_IMAGES_URL . '/' . $card_id . '.png';
        $percentage = round(($appearances / count($decks)) * 100);
        $html .= '<div class="dlg-top-card">';
        $html .= '<img src="' . esc_url($img) . '">';
        $html .= '<div>' . esc_html($card_id) . '</div>';
        $html .= '<div>' . $appearances . ' decks (' . $percentage . '%)</div>';
        $html .= '</div>';
    }
    $html .= '</div>';
    
    // Display random deck
    $html .= '<h3>Random Deck</h3>';
    $deck = $decks[array_rand($decks)];
    $html .= '<div class="dlg-cards">';
    if (isset($deck['deck']) && is_array($deck['deck'])) {
        foreach ($deck['deck'] as $card_id => $count) {
            $img = DLG_IMAGES_URL . '/' . $card_id . '.png';
            $html .= '<div class="dlg-card"><img src="' . esc_url($img) . '"><div>' . esc_html($card_id) . ' x' . $count . '</div></div>';
        }
    }
    $html .= '</div>';
    
    $html .= '<style>';
    $html .= '.dlg-top-cards{display:flex;flex-wrap:wrap;gap:10px;margin:20px 0}';
    $html .= '.dlg-top-card{width:150px;text-align:center;font-size:12px}';
    $html .= '.dlg-top-card img{width:100%;height:auto}';
    $html .= '.dlg-cards{display:flex;flex-wrap:wrap;gap:10px;margin:20px 0}';
    $html .= '.dlg-card{width:150px;font-size:12px}';
    $html .= '.dlg-card img{width:100%;height:auto}';
    $html .= '</style></div>';
    
    return $html;
}

add_shortcode('leader_gallery', 'dlg_leader_gallery_shortcode');
add_shortcode('deck_viewer', 'dlg_deck_viewer_shortcode');
EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
systemctl restart httpd
