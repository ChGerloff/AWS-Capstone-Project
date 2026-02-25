#!/bin/bash
yum update -y
amazon-linux-extras install -y php8.2
yum install -y httpd php-mysqlnd wget unzip mysql python3 python3-pip

# Install Python packages
pip3 install numpy

systemctl enable httpd
systemctl start httpd

# Wait for RDS to be available
RDS_ENDPOINT="${rds_endpoint}"
until mysqladmin ping -h "${rds_address}" -u wpuser -p'StrongPass123!' >/dev/null 2>&1; do
  echo "Waiting for RDS..."
  sleep 5
done

cd /var/www/html
wget https://wordpress.org/latest.tar.gz
tar -xzf latest.tar.gz
cp -r wordpress/* .
rm -rf wordpress latest.tar.gz

cp wp-config-sample.php wp-config.php
sed -i "s/database_name_here/wordpress/" wp-config.php
sed -i "s/username_here/wpuser/" wp-config.php
sed -i "s/password_here/StrongPass123!/" wp-config.php
sed -i "s/localhost/${rds_address}/" wp-config.php
sed -i "/<?php/a define('WP_MEMORY_LIMIT', '256M');" wp-config.php

mkdir -p wp-content/decks
# Download leaders list
wget https://ger-op-decks-images.s3.eu-north-1.amazonaws.com/leaders.json -O wp-content/decks/leaders.json

# Create Python deck generator script
cat > wp-content/decks/generate_deck.py << 'EOPY'
import pickle
import sys
import json
import urllib.request

leader_id = sys.argv[1]
model_url = f'https://ger-op-decks-images.s3.eu-north-1.amazonaws.com/model_{leader_id}.pkl'

try:
    with urllib.request.urlopen(model_url) as response:
        model_data = pickle.loads(response.read())
    
    import numpy as np
    deck = {leader_id: 1}
    sorted_cards = sorted(model_data['card_probabilities'].items(), key=lambda x: x[1], reverse=True)
    total_cards = 1
    
    for card_id, prob in sorted_cards:
        if card_id == leader_id or total_cards >= 50:
            continue
        if np.random.random() < prob:
            count = min(model_data['avg_card_counts'].get(card_id, 1), 50 - total_cards, 4)
            if count > 0:
                deck[card_id] = count
                total_cards += count
    
    while total_cards < 50:
        for card_id, prob in sorted_cards:
            if card_id == leader_id:
                continue
            if card_id in deck and deck[card_id] < 4:
                deck[card_id] += 1
                total_cards += 1
            elif card_id not in deck:
                deck[card_id] = 1
                total_cards += 1
            if total_cards >= 50:
                break
        if total_cards < 50:
            break
    
    print(json.dumps(deck))
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOPY

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
    $atts = shortcode_atts(array('target' => 'deck-viewer'), $atts);
    $leaders = dlg_load_leaders();
    if (empty($leaders)) return '<p>No leaders available.</p>';
    
    // Get the target page URL
    $target_page = $atts['target'];
    $deck_page_url = home_url('/index.php/' . $target_page . '/');
    
    $html = '<div class="dlg-leader-gallery">';
    foreach ($leaders as $leader) {
        $img = DLG_IMAGES_URL . '/' . $leader['id'] . '.png';
        $url = add_query_arg('leader', $leader['id'], $deck_page_url);
        $html .= '<div class="dlg-leader-card">';
        $html .= '<a href="' . esc_url($url) . '">';
        $html .= '<img src="' . esc_url($img) . '" alt="' . esc_attr($leader['name']) . '">';
        $html .= '<div class="dlg-leader-name">' . esc_html($leader['name']) . '</div>';
        $html .= '</a></div>';
    }
    $html .= '</div>';
    $html .= '<style>';
    $html .= '.dlg-leader-gallery{display:grid;grid-template-columns:repeat(5,1fr);gap:15px;margin:20px 0}';
    $html .= '.dlg-leader-card{text-align:center;border:2px solid #ddd;border-radius:8px;padding:10px;transition:transform 0.2s}';
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
    
    // Filter decks with minimum 45 cards
    $filtered_decks = array();
    foreach ($decks as $deck) {
        if (isset($deck['deck']) && is_array($deck['deck'])) {
            $total_cards = array_sum($deck['deck']);
            if ($total_cards >= 45) {
                $filtered_decks[] = $deck;
            }
        }
    }
    
    if (empty($filtered_decks)) {
        return '<p>No decks with 45+ cards found for this leader.</p>';
    }
    
    $leaders = dlg_load_leaders();
    
    // Get leader name from leaders.json
    $leader_name = 'Unknown';
    foreach ($leaders as $leader) {
        if ($leader['id'] === $leader_id) {
            $leader_name = $leader['name'];
            break;
        }
    }
    
    // Leader dropdown
    $html = '<div class="dlg-controls">';
    $html .= '<form method="get" action="" style="display:inline-block;margin-right:10px;">';
    $html .= '<select name="leader" onchange="this.form.submit()">';
    foreach ($leaders as $leader) {
        $selected = ($leader['id'] === $leader_id) ? 'selected' : '';
        $html .= '<option value="' . esc_attr($leader['id']) . '" ' . $selected . '>' . esc_html($leader['name']) . '</option>';
    }
    $html .= '</select></form></div>';
    
    $html .= '<h2>' . esc_html($leader_name) . '</h2>';
    $html .= '<p>Total Decks: ' . count($filtered_decks) . '</p>';
    
    // Random deck button
    $html .= '<h3>Random Deck</h3>';
    $html .= '<form method="get" action="" style="margin-bottom:20px;">';
    $html .= '<input type="hidden" name="leader" value="' . esc_attr($leader_id) . '">';
    $html .= '<button type="submit">New Random Deck</button>';
    $html .= '</form>';
    
    // Display random deck with leader card on the left
    $deck = $filtered_decks[array_rand($filtered_decks)];
    $total_cards = isset($deck['deck']) ? array_sum($deck['deck']) : 0;
    
    $html .= '<div class="dlg-deck-container">';
    $html .= '<div class="dlg-leader-card-display">';
    $html .= '<img src="' . esc_url(DLG_IMAGES_URL . '/' . $leader_id . '.png') . '">';
    $html .= '</div>';
    $html .= '<div class="dlg-cards">';
    if (isset($deck['deck']) && is_array($deck['deck'])) {
        foreach ($deck['deck'] as $card_id => $count) {
            if ($card_id === $leader_id) continue;
            $img = DLG_IMAGES_URL . '/' . $card_id . '.png';
            $html .= '<div class="dlg-card"><img src="' . esc_url($img) . '" class="dlg-card-img"><div>' . esc_html($card_id) . ' x' . $count . '</div></div>';
        }
    }
    $html .= '</div></div>';
    $html .= '<p><strong>Total Cards: ' . $total_cards . '</strong></p>';
    
    // Calculate card statistics
    $card_counts = array();
    foreach ($filtered_decks as $deck) {
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
    $top_cards = array_slice($card_counts, 0, 16, true);
    
    // Display statistics
    $html .= '<div class="dlg-stats">';
    $html .= '<h3>Most Played Cards</h3>';
    $html .= '<div class="dlg-top-cards">';
    foreach ($top_cards as $card_id => $appearances) {
        $img = DLG_IMAGES_URL . '/' . $card_id . '.png';
        $percentage = round(($appearances / count($filtered_decks)) * 100);
        $html .= '<div class="dlg-top-card">';
        $html .= '<img src="' . esc_url($img) . '" class="dlg-card-img">';
        $html .= '<div>' . esc_html($card_id) . '</div>';
        $html .= '<div>' . $appearances . ' decks (' . $percentage . '%)</div>';
        $html .= '</div>';
    }
    $html .= '</div></div>';;;
    
    $html .= '<style>';
    $html .= '.dlg-controls{margin:20px 0}';
    $html .= '.dlg-top-cards{display:flex;flex-wrap:wrap;gap:10px;margin:20px 0}';
    $html .= '.dlg-top-card{width:150px;text-align:center;font-size:12px}';
    $html .= '.dlg-top-card img{width:100%;height:auto}';
    $html .= '.dlg-deck-container{display:flex;gap:20px;margin:20px 0}';
    $html .= '.dlg-leader-card-display{flex-shrink:0}';
    $html .= '.dlg-leader-card-display img{width:200px;height:auto}';
    $html .= '.dlg-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;flex:1}';
    $html .= '.dlg-card{font-size:12px;position:relative}';
    $html .= '.dlg-card img{width:100%;height:auto}';
    $html .= '.dlg-card-img{cursor:pointer}';
    $html .= '</style>';
    $html .= '<script>';
    $html .= 'document.addEventListener("DOMContentLoaded",function(){';
    $html .= 'let zoomedImg=null;';
    $html .= 'document.querySelectorAll(".dlg-card-img").forEach(img=>{';
    $html .= 'img.addEventListener("mouseenter",function(e){';
    $html .= 'zoomedImg=document.createElement("img");';
    $html .= 'zoomedImg.src=this.src;';
    $html .= 'zoomedImg.style.position="fixed";';
    $html .= 'zoomedImg.style.width="400px";';
    $html .= 'zoomedImg.style.zIndex="10000";';
    $html .= 'zoomedImg.style.pointerEvents="none";';
    $html .= 'document.body.appendChild(zoomedImg);';
    $html .= '});';
    $html .= 'img.addEventListener("mousemove",function(e){';
    $html .= 'if(zoomedImg){zoomedImg.style.left=(e.clientX+10)+"px";zoomedImg.style.top=(e.clientY+10)+"px";}';
    $html .= '});';
    $html .= 'img.addEventListener("mouseleave",function(){';
    $html .= 'if(zoomedImg){zoomedImg.remove();zoomedImg=null;}';
    $html .= '});';
    $html .= '});';
    $html .= '});';
    $html .= '</script>';
    
    return $html;
}


function dlg_ai_deck_generator_shortcode($atts) {
    if (!isset($_GET['leader']) || empty($_GET['leader'])) {
        return '<p>Please select a leader from the gallery.</p>';
    }
    
    $leader_id = sanitize_text_field($_GET['leader']);
    $leaders = dlg_load_leaders();
    
    $leader_name = 'Unknown';
    foreach ($leaders as $leader) {
        if ($leader['id'] === $leader_id) {
            $leader_name = $leader['name'];
            break;
        }
    }
    
    $html = '<div class="dlg-controls">';
    $html .= '<form method="get" action="" style="display:inline-block;margin-right:10px;">';
    $html .= '<input type="hidden" name="page_id" value="' . get_the_ID() . '">';
    $html .= '<select name="leader" onchange="this.form.submit()">';
    foreach ($leaders as $leader) {
        $selected = ($leader['id'] === $leader_id) ? 'selected' : '';
        $html .= '<option value="' . esc_attr($leader['id']) . '" ' . $selected . '>' . esc_html($leader['name']) . '</option>';
    }
    $html .= '</select></form></div>';
    
    $html .= '<h2>AI Generated Deck - ' . esc_html($leader_name) . '</h2>';
    
    $html .= '<form method="get" action="" style="margin-bottom:20px;">';
    $html .= '<input type="hidden" name="page_id" value="' . get_the_ID() . '">';
    $html .= '<input type="hidden" name="leader" value="' . esc_attr($leader_id) . '">';
    $html .= '<button type="submit">Generate New AI Deck</button>';
    $html .= '</form>';
    
    $python_script = WP_CONTENT_DIR . '/decks/generate_deck.py';
    $command = "python3 " . escapeshellarg($python_script) . " " . escapeshellarg($leader_id);
    $output = shell_exec($command);
    $deck_data = json_decode($output, true);
    
    if (isset($deck_data['error'])) {
        $html .= '<p>Error generating deck: ' . esc_html($deck_data['error']) . '</p>';
        return $html;
    }
    
    if (empty($deck_data)) {
        $html .= '<p>Could not generate deck for this leader.</p>';
        return $html;
    }
    
    $total_cards = array_sum($deck_data);
    
    $html .= '<div class="dlg-deck-container">';
    $html .= '<div class="dlg-leader-card-display">';
    $html .= '<img src="' . esc_url(DLG_IMAGES_URL . '/' . $leader_id . '.png') . '">';
    $html .= '</div>';
    $html .= '<div class="dlg-cards">';
    foreach ($deck_data as $card_id => $count) {
        if ($card_id === $leader_id) continue;
        $img = DLG_IMAGES_URL . '/' . $card_id . '.png';
        $html .= '<div class="dlg-card"><img src="' . esc_url($img) . '" class="dlg-card-img"><div>' . esc_html($card_id) . ' x' . $count . '</div></div>';
    }
    $html .= '</div></div>';
    $html .= '<p><strong>Total Cards: ' . $total_cards . '</strong></p>';
    
    $html .= '<style>';
    $html .= '.dlg-controls{margin:20px 0}';
    $html .= '.dlg-deck-container{display:flex;gap:20px;margin:20px 0}';
    $html .= '.dlg-leader-card-display{flex-shrink:0}';
    $html .= '.dlg-leader-card-display img{width:200px;height:auto}';
    $html .= '.dlg-cards{display:grid;grid-template-columns:repeat(4,1fr);gap:10px;flex:1}';
    $html .= '.dlg-card{font-size:12px;position:relative}';
    $html .= '.dlg-card img{width:100%;height:auto}';
    $html .= '.dlg-card-img{cursor:pointer}';
    $html .= '</style>';
    $html .= '<script>';
    $html .= 'document.addEventListener("DOMContentLoaded",function(){';
    $html .= 'let zoomedImg=null;';
    $html .= 'document.querySelectorAll(".dlg-card-img").forEach(img=>{';
    $html .= 'img.addEventListener("mouseenter",function(e){';
    $html .= 'zoomedImg=document.createElement("img");';
    $html .= 'zoomedImg.src=this.src;';
    $html .= 'zoomedImg.style.position="fixed";';
    $html .= 'zoomedImg.style.width="400px";';
    $html .= 'zoomedImg.style.zIndex="10000";';
    $html .= 'zoomedImg.style.pointerEvents="none";';
    $html .= 'document.body.appendChild(zoomedImg);';
    $html .= '});';
    $html .= 'img.addEventListener("mousemove",function(e){';
    $html .= 'if(zoomedImg){zoomedImg.style.left=(e.clientX+10)+"px";zoomedImg.style.top=(e.clientY+10)+"px";}';
    $html .= '});';
    $html .= 'img.addEventListener("mouseleave",function(){';
    $html .= 'if(zoomedImg){zoomedImg.remove();zoomedImg=null;}';
    $html .= '});';
    $html .= '});';
    $html .= '});';
    $html .= '</script>';
    
    return $html;
}

add_shortcode('leader_gallery', 'dlg_leader_gallery_shortcode');
add_shortcode('deck_viewer', 'dlg_deck_viewer_shortcode');
add_shortcode('ai_deck_generator', 'dlg_ai_deck_generator_shortcode');

EOPHP

chown -R apache:apache /var/www/html
chmod -R 755 /var/www/html
systemctl restart httpd
