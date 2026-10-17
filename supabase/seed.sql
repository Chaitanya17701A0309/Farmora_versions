-- Farmora seed data (run by `supabase db reset` locally; run once in production via SQL editor).
-- To create the first admin, sign up normally, then:
--   update public.profiles set role = 'admin'
--    where id = (select id from auth.users where email = 'founder@example.com');

-- Marketplace categories
insert into public.categories (slug, name_i18n, sort_order) values
  ('honey',   '{"en":"Honey","te":"తేనె","ta":"தேன்","hi":"शहद"}', 1),
  ('ghee',    '{"en":"Ghee","te":"నెయ్యి","ta":"நெய்","hi":"घी"}', 2),
  ('oils',    '{"en":"Oils","te":"నూనెలు","ta":"எண்ணெய்கள்","hi":"तेल"}', 3),
  ('millets', '{"en":"Millets","te":"చిరుధాన్యాలు","ta":"சிறுதானியங்கள்","hi":"मोटा अनाज"}', 4),
  ('pulses',  '{"en":"Pulses","te":"పప్పులు","ta":"பருப்பு வகைகள்","hi":"दालें"}', 5),
  ('spices',  '{"en":"Spices","te":"సుగంధ ద్రవ్యాలు","ta":"மசாலா பொருட்கள்","hi":"मसाले"}', 6)
on conflict (slug) do nothing;

-- Demand cycles
insert into demand.cycles (name, season, starts_on, ends_on, is_current) values
  ('Rabi 2026-27',  'rabi',   '2026-10-01', '2027-03-31', true),
  ('Zaid 2027',     'zaid',   '2027-04-01', '2027-06-14', false),
  ('Kharif 2027',   'kharif', '2027-06-15', '2027-09-30', false)
on conflict (name) do nothing;

-- Demand items: crops
insert into demand.items (kind, slug, name, name_i18n, category, seasons) values
  ('crop', 'groundnut',      'Groundnut',      '{"te":"వేరుశనగ","ta":"நிலக்கடலை","hi":"मूंगफली"}',            'oilseeds',   '{kharif,rabi}'),
  ('crop', 'foxtail-millet', 'Foxtail Millet', '{"te":"కొర్రలు","ta":"தினை","hi":"कंगनी"}',                    'millets',    '{kharif}'),
  ('crop', 'organic-tomato', 'Organic Tomato', '{"te":"సేంద్రియ టమాటా","ta":"இயற்கை தக்காளி","hi":"जैविक टमाटर"}', 'vegetables', '{kharif,rabi,zaid}'),
  ('crop', 'turmeric',       'Turmeric',       '{"te":"పసుపు","ta":"மஞ்சள்","hi":"हल्दी"}',                    'spices',     '{kharif}'),
  ('crop', 'finger-millet',  'Finger Millet (Ragi)', '{"te":"రాగులు","ta":"கேழ்வரகு","hi":"रागी"}',            'millets',    '{kharif,rabi}'),
  ('crop', 'little-millet',  'Little Millet',  '{"te":"సామలు","ta":"சாமை","hi":"कुटकी"}',                     'millets',    '{kharif}'),
  ('crop', 'kodo-millet',    'Kodo Millet',    '{"te":"అరికెలు","ta":"வரகு","hi":"कोदो"}',                    'millets',    '{kharif}'),
  ('crop', 'pearl-millet',   'Pearl Millet',   '{"te":"సజ్జలు","ta":"கம்பு","hi":"बाजरा"}',                    'millets',    '{kharif,zaid}'),
  ('crop', 'sorghum',        'Sorghum',        '{"te":"జొన్నలు","ta":"சோளம்","hi":"ज्वार"}',                   'millets',    '{kharif,rabi}'),
  ('crop', 'red-gram',       'Red Gram (Toor)', '{"te":"కందులు","ta":"துவரை","hi":"अरहर"}',                   'pulses',     '{kharif}'),
  ('crop', 'green-gram',     'Green Gram',     '{"te":"పెసలు","ta":"பாசிப்பயறு","hi":"मूंग"}',                 'pulses',     '{kharif,rabi,zaid}'),
  ('crop', 'black-gram',     'Black Gram',     '{"te":"మినుములు","ta":"உளுந்து","hi":"उड़द"}',                 'pulses',     '{kharif,rabi}'),
  ('crop', 'red-chilli',     'Red Chilli',     '{"te":"ఎండు మిర్చి","ta":"மிளகாய்","hi":"लाल मिर्च"}',           'spices',     '{kharif,rabi}'),
  ('crop', 'onion',          'Onion',          '{"te":"ఉల్లిపాయ","ta":"வெங்காயம்","hi":"प्याज"}',               'vegetables', '{kharif,rabi}'),
  ('crop', 'brinjal',        'Brinjal',        '{"te":"వంకాయ","ta":"கத்தரிக்காய்","hi":"बैंगन"}',                'vegetables', '{year_round}'),
  ('crop', 'mango',          'Mango',          '{"te":"మామిడి","ta":"மாம்பழம்","hi":"आम"}',                    'fruits',     '{zaid}')
on conflict (slug) do nothing;

-- Demand items: products
insert into demand.items (kind, slug, name, name_i18n, category, seasons) values
  ('product', 'forest-honey',         'Forest Honey',                '{"te":"అడవి తేనె","ta":"காட்டுத் தேன்","hi":"जंगली शहद"}',                          'honey', '{year_round}'),
  ('product', 'a2-cow-ghee',          'A2 Cow Ghee',                 '{"te":"A2 ఆవు నెయ్యి","ta":"A2 பசு நெய்","hi":"A2 गाय का घी"}',                      'ghee',  '{year_round}'),
  ('product', 'cold-pressed-groundnut-oil', 'Cold-pressed Groundnut Oil', '{"te":"గానుగ వేరుశనగ నూనె","ta":"மரச்செக்கு கடலை எண்ணெய்","hi":"कच्ची घानी मूंगफली तेल"}', 'oils', '{year_round}'),
  ('product', 'cold-pressed-sesame-oil',    'Cold-pressed Sesame Oil',    '{"te":"గానుగ నువ్వుల నూనె","ta":"மரச்செக்கு நல்லெண்ணெய்","hi":"कच्ची घानी तिल का तेल"}',  'oils', '{year_round}'),
  ('product', 'turmeric-powder',      'Turmeric Powder',             '{"te":"పసుపు పొడి","ta":"மஞ்சள் தூள்","hi":"हल्दी पाउडर"}',                        'spices', '{year_round}'),
  ('product', 'millet-flour-mix',     'Millet Flour Mix',            '{"te":"చిరుధాన్యాల పిండి","ta":"சிறுதானிய மாவு","hi":"मोटे अनाज का आटा"}',             'millets', '{year_round}')
on conflict (slug) do nothing;

-- Sample poll
with p as (
  insert into demand.polls (title, title_i18n, description, status, starts_at, ends_at)
  values ('Sankranti 2027: what should our farmers grow for you?',
          '{"te":"సంక్రాంతి 2027: మా రైతులు మీ కోసం ఏమి పండించాలి?","ta":"பொங்கல் 2027: எங்கள் விவசாயிகள் உங்களுக்காக எதை விளைவிக்க வேண்டும்?","hi":"संक्रांति 2027: हमारे किसान आपके लिए क्या उगाएं?"}',
          'Help farmers plan the next harvest. Takes 1 minute.',
          'active', now(), '2027-01-10 23:59:59+05:30')
  returning id
)
insert into demand.poll_questions (poll_id, sort_order, prompt, type, options, is_required)
select p.id, q.sort_order, q.prompt, q.type::demand.question_type, q.options::jsonb, q.sort_order <> 4
  from p
 cross join (values
   (1, 'Which crop would you most like to buy directly from a farmer?', 'single_choice',
       '[{"id":1,"label":"Groundnut"},{"id":2,"label":"Foxtail Millet"},{"id":3,"label":"Organic Tomato"},{"id":4,"label":"Turmeric"}]'),
   (2, 'Which products would you subscribe to every month?', 'multi_choice',
       '[{"id":1,"label":"Honey"},{"id":2,"label":"Ghee"},{"id":3,"label":"Cold-pressed oils"},{"id":4,"label":"Millets"},{"id":5,"label":"Pulses"}]'),
   (3, 'How important is organic certification to you?', 'rating', '[]'),
   (4, 'Anything else you wish farmers grew?', 'text', '[]')
 ) as q(sort_order, prompt, type, options);
