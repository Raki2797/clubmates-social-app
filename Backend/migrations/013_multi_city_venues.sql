DROP TABLE IF EXISTS venue_seed_multi_city;

CREATE TEMP TABLE venue_seed_multi_city (
  name TEXT,
  city TEXT,
  neighborhood TEXT,
  vibe TEXT,
  music TEXT,
  symbol_name TEXT,
  gradient_hex TEXT[],
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  checkin_radius_meters INTEGER
);

INSERT INTO venue_seed_multi_city (
  name,
  city,
  neighborhood,
  vibe,
  music,
  symbol_name,
  gradient_hex,
  latitude,
  longitude,
  checkin_radius_meters
)
VALUES
    -- Bangalore (30)
    ('Toit Indiranagar', 'Bangalore', 'Indiranagar', 'Iconic brewpub crowd', 'Rock / Pop', 'mug.fill', ARRAY['854D0E', 'FACC15'], 12.9793, 77.6407, 200),
    ('Byg Brewski Sarjapur', 'Bangalore', 'Sarjapur Road', 'Large-format brewery nights', 'Commercial / House', 'building.2.fill', ARRAY['0F766E', '14B8A6'], 12.9064, 77.6821, 200),
    ('Arbor Brewing Company', 'Bangalore', 'Ashok Nagar', 'Craft beer social scene', 'Indie / Pop', 'leaf.fill', ARRAY['15803D', '84CC16'], 12.9708, 77.6090, 200),
    ('Skyye UB City', 'Bangalore', 'Ashok Nagar', 'Rooftop party energy', 'EDM / Commercial', 'sparkles', ARRAY['2563EB', 'A855F7'], 12.9717, 77.5959, 200),
    ('Windmills Craftworks', 'Bangalore', 'Whitefield', 'Brewery and live jazz', 'Jazz / Live', 'music.mic', ARRAY['1E3A8A', '06B6D4'], 12.9820, 77.7277, 200),
    ('The Bier Library', 'Bangalore', 'Koramangala', 'Garden brewery hangout', 'Pop / Commercial', 'mug.fill', ARRAY['047857', '10B981'], 12.9351, 77.6160, 200),
    ('Social Koramangala', 'Bangalore', 'Koramangala', 'Young social crowd', 'Commercial / Pop', 'bolt.fill', ARRAY['DC2626', 'F97316'], 12.9352, 77.6146, 200),
    ('Social Indiranagar', 'Bangalore', 'Indiranagar', 'Startup and nightlife crowd', 'Commercial / House', 'bolt.fill', ARRAY['2563EB', '06B6D4'], 12.9784, 77.6408, 200),
    ('Pecos', 'Bangalore', 'Brigade Road', 'Classic pub atmosphere', 'Rock / Retro', 'music.mic', ARRAY['7C2D12', 'F59E0B'], 12.9722, 77.6071, 200),
    ('Bobs Bar', 'Bangalore', 'Indiranagar', 'Casual party crowd', 'Rock / Pop', 'mug.fill', ARRAY['92400E', 'FBBF24'], 12.9719, 77.6412, 200),
    ('Big Pitcher', 'Bangalore', 'Old Airport Road', 'Large brewery venue', 'Commercial / Live', 'building.2.fill', ARRAY['15803D', '84CC16'], 12.9595, 77.6504, 200),
    ('Stories Brewery', 'Bangalore', 'BTM Layout', 'Youth nightlife destination', 'EDM / Commercial', 'sparkles', ARRAY['7E22CE', 'EC4899'], 12.9138, 77.6092, 200),
    ('NoLimmits Lounge', 'Bangalore', 'Brigade Road', 'High-energy club nights', 'EDM / Commercial', 'sparkles', ARRAY['7E22CE', 'F472B6'], 12.9715, 77.6070, 200),
    ('High Ultra Lounge', 'Bangalore', 'MG Road', 'Rooftop luxury vibes', 'House / EDM', 'cloud.fill', ARRAY['1D4ED8', '38BDF8'], 12.9750, 77.6055, 200),
    ('The Sugar Factory', 'Bangalore', 'Koramangala', 'Glamorous cocktail scene', 'Pop / Hip-hop', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 12.9355, 77.6210, 200),
    ('XU', 'Bangalore', 'Indiranagar', 'Upscale nightclub energy', 'EDM / Commercial', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 12.9780, 77.6350, 200),
    ('LOFT 38', 'Bangalore', 'Indiranagar', 'Trendy bar and dance', 'Commercial / House', 'bolt.fill', ARRAY['DC2626', 'F97316'], 12.9775, 77.6420, 200),
    ('Hard Rock Cafe', 'Bangalore', 'St. Marks Road', 'Live rock atmosphere', 'Rock / Live', 'music.mic', ARRAY['B91C1C', 'F97316'], 12.9758, 77.6065, 200),
    ('Social Whitefield', 'Bangalore', 'Whitefield', 'Casual young crowd', 'Pop / Commercial', 'bolt.fill', ARRAY['2563EB', '06B6D4'], 12.9960, 77.7200, 200),
    ('Effingut Whitefield', 'Bangalore', 'Whitefield', 'Craft beer and vibes', 'Indie / Pop', 'mug.fill', ARRAY['065F46', '84CC16'], 12.9890, 77.7250, 200),
    ('Boho', 'Bangalore', 'Koramangala', 'Chill lounge nights', 'House / Lounge', 'moon.stars.fill', ARRAY['4338CA', '06B6D4'], 12.9320, 77.6230, 200),
    ('Drunken Daddy', 'Bangalore', 'JP Nagar', 'Fun casual parties', 'Commercial / Pop', 'flame.fill', ARRAY['B91C1C', 'F97316'], 12.8900, 77.5850, 200),
    ('Tipsy Bull', 'Bangalore', 'HSR Layout', 'Youthful bar energy', 'Hip-hop / Pop', 'bolt.fill', ARRAY['BE123C', 'F43F5E'], 12.9080, 77.6250, 200),
    ('Kaze', 'Bangalore', 'Ashok Nagar', 'Rooftop views and music', 'House / Commercial', 'sunset.fill', ARRAY['C2410C', 'F97316'], 12.9700, 77.5980, 200),
    ('Marquis', 'Bangalore', 'Outer Ring Road', 'Modern nightclub scene', 'EDM / Commercial', 'sparkles', ARRAY['9333EA', 'EC4899'], 12.9200, 77.6800, 200),
    ('HOD Koramangala', 'Bangalore', 'Koramangala', 'High-energy DJ nights', 'EDM / House', 'music.note.house.fill', ARRAY['7E22CE', 'F472B6'], 12.9360, 77.6150, 200),
    ('The Raft', 'Bangalore', 'MG Road', 'Live music hangout', 'Rock / Live', 'music.mic', ARRAY['1E3A8A', '06B6D4'], 12.9740, 77.6050, 200),
    ('Sunburn Union', 'Bangalore', 'Whitefield', 'Festival-style parties', 'EDM / Commercial', 'bolt.circle.fill', ARRAY['DC2626', 'F97316'], 12.9850, 77.7300, 200),
    ('Gillys Redefined', 'Bangalore', 'Koramangala', 'Fandom and fun nights', 'Pop / Commercial', 'sparkles', ARRAY['7E22CE', 'EC4899'], 12.9340, 77.6180, 200),
    ('The Blue Room', 'Bangalore', 'Indiranagar', 'Intimate lounge vibes', 'Jazz / Live', 'music.mic', ARRAY['1E3A8A', '06B6D4'], 12.9770, 77.6380, 200),

    -- Mumbai (30)
    ('AER Mumbai', 'Mumbai', 'Worli', 'Sky-high rooftop lounge', 'House / Commercial', 'cloud.fill', ARRAY['1D4ED8', '38BDF8'], 18.9930, 72.8208, 200),
    ('Dome Mumbai', 'Mumbai', 'Marine Drive', 'Sea-facing rooftop crowd', 'House / Lounge', 'sunset.fill', ARRAY['C2410C', 'F97316'], 18.9349, 72.8242, 200),
    ('Monkey Bar Bandra', 'Mumbai', 'Bandra West', 'Playful bar energy', 'Pop / Hip-hop', 'bolt.fill', ARRAY['BE123C', 'F43F5E'], 19.0603, 72.8346, 200),
    ('145 The Mill', 'Mumbai', 'Lower Parel', 'Mill district bar nights', 'Commercial / Pop', 'building.2.fill', ARRAY['581C87', 'D946EF'], 18.9944, 72.8253, 200),
    ('Lord Of The Drinks Mumbai', 'Mumbai', 'Lower Parel', 'Large lounge crowd', 'Bollywood / Commercial', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 18.9977, 72.8305, 200),
    ('Bonobo Mumbai', 'Mumbai', 'Bandra West', 'Terrace music bar', 'House / Indie', 'moon.stars.fill', ARRAY['4338CA', '06B6D4'], 19.0606, 72.8361, 200),
    ('Dragonfly Experience', 'Mumbai', 'Andheri East', 'Premium nightclub', 'EDM / Commercial', 'sparkles', ARRAY['7E22CE', 'F472B6'], 19.1131, 72.8766, 200),
    ('Escobar', 'Mumbai', 'Bandra West', 'Rooftop party venue', 'House / Commercial', 'moon.stars.fill', ARRAY['4338CA', '06B6D4'], 19.0607, 72.8343, 200),
    ('Khar Social', 'Mumbai', 'Khar West', 'Social nightlife hub', 'Commercial / Pop', 'bolt.fill', ARRAY['DC2626', 'FB7185'], 19.0683, 72.8364, 200),
    ('Yeda Republic', 'Mumbai', 'Andheri West', 'Lively nightlife crowd', 'Bollywood / Commercial', 'music.note.house.fill', ARRAY['BE123C', 'F43F5E'], 19.1360, 72.8279, 200),
    ('Trilogy Super Club', 'Mumbai', 'Juhu', 'Luxury nightclub', 'EDM / House', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 19.1074, 72.8263, 200),
    ('The Little Easy', 'Mumbai', 'Bandra West', 'Cocktails and live music', 'Jazz / Live', 'music.mic', ARRAY['1E3A8A', '06B6D4'], 19.0615, 72.8349, 200),
    ('Kitty Su Mumbai', 'Mumbai', 'Andheri East', 'High-end club nights', 'EDM / Commercial', 'sparkles', ARRAY['9333EA', 'EC4899'], 19.1150, 72.8500, 200),
    ('Tryst Mumbai', 'Mumbai', 'Lower Parel', 'Vibrant dance floor', 'EDM / House', 'bolt.circle.fill', ARRAY['DC2626', 'F97316'], 18.9950, 72.8250, 200),
    ('Toto''s Garage', 'Mumbai', 'Bandra West', 'Rock and roll vibes', 'Rock / Live', 'music.mic', ARRAY['7C2D12', 'F59E0B'], 19.0620, 72.8300, 200),
    ('The Irish House', 'Mumbai', 'Lower Parel', 'Pub-style social scene', 'Pop / Commercial', 'mug.fill', ARRAY['92400E', 'FBBF24'], 18.9980, 72.8280, 200),
    ('Colaba Social', 'Mumbai', 'Colaba', 'Casual trendy crowd', 'Commercial / Pop', 'bolt.fill', ARRAY['2563EB', '06B6D4'], 18.9150, 72.8300, 200),
    ('Play The Lounge', 'Mumbai', 'Lower Parel', 'Upscale lounge energy', 'House / Lounge', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 18.9960, 72.8270, 200),
    ('XXO', 'Mumbai', 'Lower Parel', 'Luxury high-rise club', 'EDM / Commercial', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 18.9900, 72.8200, 200),
    ('Bastian', 'Mumbai', 'Bandra', 'Fine dining meets party', 'House / Commercial', 'flame.fill', ARRAY['B91C1C', 'F97316'], 19.0650, 72.8350, 200),
    ('One8 Commune', 'Mumbai', 'Bandra West', 'Modern bar hangout', 'Pop / Hip-hop', 'bolt.fill', ARRAY['BE123C', 'F43F5E'], 19.0580, 72.8300, 200),
    ('Bar Bank', 'Mumbai', 'Juhu', 'Beachside party vibes', 'Commercial / EDM', 'sunset.fill', ARRAY['C2410C', 'F97316'], 19.1050, 72.8250, 200),
    ('Toy Room Mumbai', 'Mumbai', 'Andheri', 'Luxury hip-hop nights', 'Hip-hop / EDM', 'sparkles', ARRAY['9333EA', 'EC4899'], 19.1100, 72.8500, 200),
    ('Neos', 'Mumbai', 'BKC', 'Sophisticated lounge', 'House / Lounge', 'moon.stars.fill', ARRAY['4338CA', '06B6D4'], 19.0700, 72.8700, 200),
    ('Hoppipola', 'Mumbai', 'Bandra', 'Casual fun crowd', 'Pop / Commercial', 'mug.fill', ARRAY['854D0E', 'FACC15'], 19.0600, 72.8350, 200),
    ('Bombay Cocktail Bar', 'Mumbai', 'Lower Parel', 'Craft cocktail scene', 'Jazz / Live', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 18.9950, 72.8260, 200),
    ('Club Illusion', 'Mumbai', 'Andheri West', 'Themed nightclub energy', 'EDM / Commercial', 'sparkles', ARRAY['7E22CE', 'F472B6'], 19.1300, 72.8300, 200),
    ('Rude Lounge', 'Mumbai', 'Andheri East', 'Late night dance floor', 'EDM / House', 'bolt.circle.fill', ARRAY['DC2626', 'F97316'], 19.1150, 72.8800, 200),
    ('Skyy Lower Parel', 'Mumbai', 'Lower Parel', 'Rooftop party spot', 'House / Commercial', 'cloud.fill', ARRAY['1D4ED8', '38BDF8'], 18.9970, 72.8250, 200),
    ('Opa Bar and Cafe', 'Mumbai', 'Bandra', 'Mediterranean party vibes', 'Commercial / Pop', 'sunset.fill', ARRAY['C2410C', 'F97316'], 19.0620, 72.8320, 200),

    -- Delhi NCR (40 total: Delhi ~20, Gurgaon ~12, Noida ~8)
    ('Kitty Su Delhi', 'Delhi', 'Barakhamba Road', 'High-energy club nights', 'EDM / Commercial', 'sparkles', ARRAY['7E22CE', 'F472B6'], 28.6307, 77.2270, 200),
    ('Privee Delhi', 'Delhi', 'Connaught Place', 'Premium club crowd', 'Bollywood / EDM', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 28.6206, 77.2184, 200),
    ('The Electric Room', 'Delhi', 'Lodhi Road', 'Late-night music lounge', 'House / Rock', 'bolt.circle.fill', ARRAY['0891B2', '4F46E5'], 28.5917, 77.2388, 200),
    ('Summer House Cafe Delhi', 'Delhi', 'Hauz Khas', 'Live and rooftop energy', 'Live / Pop', 'music.mic', ARRAY['16A34A', '84CC16'], 28.5530, 77.1949, 200),
    ('Lord Of The Drinks Delhi', 'Delhi', 'Connaught Place', 'Cocktail lounge crowd', 'Bollywood / Commercial', 'crown.fill', ARRAY['92400E', 'F59E0B'], 28.6328, 77.2196, 200),
    ('Dear Donna', 'Delhi', 'Qutub Institutional Area', 'Garden bar nights', 'House / Pop', 'leaf.fill', ARRAY['3F6212', 'A3E635'], 28.5245, 77.1855, 200),
    ('Toy Room Delhi', 'Delhi', 'Aerocity', 'Luxury nightclub', 'Hip-hop / EDM', 'sparkles', ARRAY['9333EA', 'EC4899'], 28.5539, 77.1218, 200),
    ('Soho Delhi', 'Delhi', 'Chanakyapuri', 'Premium lounge crowd', 'House / Commercial', 'crown.fill', ARRAY['2563EB', 'A855F7'], 28.5946, 77.1887, 200),
    ('Diablo Delhi', 'Delhi', 'Mehrauli', 'Upscale nightlife venue', 'EDM / Commercial', 'bolt.circle.fill', ARRAY['DC2626', 'F97316'], 28.5252, 77.1850, 200),
    ('The Junkyard Cafe', 'Delhi', 'Connaught Place', 'Casual nightlife crowd', 'Live / Pop', 'music.mic', ARRAY['047857', '10B981'], 28.6312, 77.2188, 200),
    ('My Bar Headquarters', 'Delhi', 'Connaught Place', 'Budget social crowd', 'Bollywood / Commercial', 'mug.fill', ARRAY['92400E', 'FBBF24'], 28.6315, 77.2177, 200),
    ('Cafe Delhi Heights', 'Delhi', 'Saket', 'Restaurant and nightlife mix', 'Pop / Commercial', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 28.5249, 77.2062, 200),
    ('The Piano Man', 'Delhi', 'Saket', 'Live jazz and music', 'Jazz / Live', 'music.mic', ARRAY['1E3A8A', '06B6D4'], 28.5200, 77.2200, 200),
    ('Hauz Khas Social', 'Delhi', 'Hauz Khas', 'Bohemian rooftop vibes', 'Indie / Pop', 'leaf.fill', ARRAY['15803D', '84CC16'], 28.5540, 77.1950, 200),
    ('Zoro', 'Gurgaon', 'Sector 29', 'High-energy Gurgaon parties', 'EDM / Commercial', 'sparkles', ARRAY['7E22CE', 'F472B6'], 28.4650, 77.0650, 200),
    ('Cocktails and Dreams', 'Gurgaon', 'Sector 29', 'Lively bar scene', 'House / Pop', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 28.4600, 77.0700, 200),
    ('The Empire Club', 'Gurgaon', 'Golf Course Road', 'Luxury club energy', 'EDM / House', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 28.4400, 77.1000, 200),
    ('Club BW', 'Gurgaon', 'Sector 29', 'Modern dance nights', 'Commercial / Pop', 'bolt.fill', ARRAY['DC2626', 'F97316'], 28.4620, 77.0680, 200),
    ('Imperfecto', 'Gurgaon', 'Sector 29', 'Ruin-themed parties', 'EDM / Commercial', 'flame.fill', ARRAY['B91C1C', 'F97316'], 28.4650, 77.0720, 200),
    ('Studio XO', 'Noida', 'Sector 94', 'Ultimate club experience', 'EDM / House', 'sparkles', ARRAY['9333EA', 'EC4899'], 28.5350, 77.3700, 200),
    ('Millionaire The Lux Club', 'Noida', 'Sector 94', 'Luxury nightlife', 'Hip-hop / EDM', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 28.5400, 77.3650, 200),
    ('Toy Boy Noida', 'Noida', 'Sector 18', 'Fun youthful crowd', 'Pop / Commercial', 'bolt.fill', ARRAY['BE123C', 'F43F5E'], 28.5700, 77.3250, 200),
    ('Diablo Noida', 'Noida', 'Sector 94', 'Chic edgy luxury', 'EDM / Commercial', 'bolt.circle.fill', ARRAY['DC2626', 'F97316'], 28.5350, 77.3680, 200),
    ('Impulse Noida', 'Noida', 'Sector 62', 'Vibrant party spot', 'Commercial / House', 'music.note.house.fill', ARRAY['7E22CE', 'F472B6'], 28.6200, 77.3700, 200),
    -- Pune (20)
    ('Toit Pune', 'Pune', 'Kalyani Nagar', 'Brewpub social crowd', 'Rock / Pop', 'mug.fill', ARRAY['854D0E', 'FACC15'], 18.5467, 73.9050, 200),
    ('High Spirits Cafe', 'Pune', 'Koregaon Park', 'Live gigs and dance nights', 'Live / Indie', 'music.note.house.fill', ARRAY['7C3AED', 'EC4899'], 18.5361, 73.8930, 200),
    ('Elephant & Co Kalyani Nagar', 'Pune', 'Kalyani Nagar', 'Neighborhood cocktail bar', 'Commercial / Pop', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 18.5485, 73.9035, 200),
    ('Independence Brewing Company', 'Pune', 'Balewadi', 'Craft beer groups', 'Pop / Commercial', 'mug.fill', ARRAY['065F46', '84CC16'], 18.5711, 73.7750, 200),
    ('Effingut Koregaon Park', 'Pune', 'Koregaon Park', 'Brewpub nightlife', 'Rock / Commercial', 'flame.fill', ARRAY['B91C1C', 'F97316'], 18.5369, 73.8939, 200),
    ('Mi-a-Mi Pune', 'Pune', 'Senapati Bapat Road', 'Upscale club nights', 'EDM / Commercial', 'sparkles', ARRAY['9333EA', 'DB2777'], 18.5324, 73.8298, 200),
    ('The Urban Foundry', 'Pune', 'Balewadi', 'Trendy nightlife venue', 'Commercial / Pop', 'building.2.fill', ARRAY['0F766E', '14B8A6'], 18.5701, 73.7742, 200),
    ('The House Of Medici', 'Pune', 'Viman Nagar', 'Premium nightclub', 'EDM / Commercial', 'crown.fill', ARRAY['7E22CE', 'F472B6'], 18.5677, 73.9143, 200),
    ('SWIG Pune', 'Pune', 'Koregaon Park', 'Cocktail-focused crowd', 'House / Lounge', 'wineglass.fill', ARRAY['BE185D', 'FB7185'], 18.5365, 73.8937, 200),
    ('Penthouze Pune', 'Pune', 'Baner', 'Rooftop nightlife', 'EDM / House', 'cloud.fill', ARRAY['1D4ED8', '38BDF8'], 18.5598, 73.7868, 200),
    -- Goa (25)
    ('Titos', 'Goa', 'Baga', 'Tourist nightlife hotspot', 'Commercial / EDM', 'sparkles', ARRAY['9333EA', 'EC4899'], 15.5554, 73.7512, 200),
    ('Mambos', 'Goa', 'Baga', 'Beach party destination', 'EDM / Commercial', 'music.note.house.fill', ARRAY['7E22CE', 'F472B6'], 15.5557, 73.7518, 200),
    ('SinQ Night Club', 'Goa', 'Candolim', 'Luxury nightlife venue', 'House / EDM', 'crown.fill', ARRAY['6D28D9', 'F59E0B'], 15.5150, 73.7684, 200),
    ('HillTop Goa', 'Goa', 'Vagator', 'Psytrance party venue', 'Psytrance', 'bolt.circle.fill', ARRAY['DC2626', 'F97316'], 15.5978, 73.7395, 200);

INSERT INTO venues (name, city, neighborhood, vibe, music, symbol_name, gradient_hex, latitude, longitude, checkin_radius_meters)
SELECT name, city, neighborhood, vibe, music, symbol_name, gradient_hex, latitude, longitude, checkin_radius_meters
FROM venue_seed_multi_city seed
WHERE NOT EXISTS (
  SELECT 1 FROM venues v WHERE LOWER(v.name) = LOWER(seed.name)
);

UPDATE venues v 
SET city = seed.city, 
    neighborhood = seed.neighborhood, 
    vibe = seed.vibe, 
    music = seed.music, 
    symbol_name = seed.symbol_name, 
    gradient_hex = seed.gradient_hex, 
    latitude = seed.latitude, 
    longitude = seed.longitude, 
    checkin_radius_meters = seed.checkin_radius_meters,
    is_active = true 
FROM venue_seed_multi_city seed 
WHERE LOWER(v.name) = LOWER(seed.name);

DROP TABLE IF EXISTS venue_seed_multi_city;
