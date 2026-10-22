"""Suggested adjustment-engine role from a food's name, following the conventions the team used for the
existing library (seed/food_roles_v2.csv). Used only to SUGGEST roles for new foods; a dietitian confirms.
Checked against the existing library: see the agreement figure printed by build_changeset.py."""
import re

W = lambda words: r"\b(" + words + r")\b"
RULES = [  # first match wins; order matters
    # flavour items that would otherwise look like fat / protein / carb
    ("flavour_base", W(r"vinegar|dressing|sauce|peppercorns?|nutritional yeast|mustard seeds?|coating|olive oil spray|infused (olive )?oil|chilli oil|stock|stock cube|stock pot|broth|bouillon|gravy|"
                       r"fish sauce|oyster sauce|soy sauce|soy|kecap manis|hoisin|tahini|pesto|pesto sauce|miso( paste)?|paste|fried shallots?|"
                       r"onion powder|garlic powder|curry powder|chilli powder|five spice|garam masala|seasoning|spices?|mixed spice")),
    ("adjustable_fat", W(r"cream cheese|coconut milk|coconut cream")),
    ("adjustable_carb", W(r"(high[- ])?protein (pasta|wrap|pita|pita bread|bread)|smart protein pasta|chocolate|cocoa|nesquik|ice cream|custard|marshmallow|cordial|red bean paste|jam|marmalade|honey|syrup|molasses|sugar|"
                          r"biscuits?|scotch finger|cookies?|cake|pancakes?|pikelets?|waffles?|pizza|ravioli")),
    ("adjustable_protein", W(r"protein( powder| electrolyte)?|collagen|whey|beef|veal|lamb|pork|ham|bacon|salami|pastrami|chorizo|prosciutto|"
                             r"chicken|turkey|duck|kangaroo|venison|meatballs?|fish|salmon|tuna|mackerel|sardines?|anchovies|barramundi|snapper|"
                             r"flathead|grenadier|hoki|basa|ling|trout|kingfish|whiting|roe|prawns?|shrimp|squid|calamari|octopus|mussels?|"
                             r"oysters?|scallops?|crab|lobster|eggs?|egg white|egg yolk|tofu|tempeh|beans?|lentils?|chickpeas?|split peas|"
                             r"edamame|soy beans|falafel|hummus|meat alternative|cheese|cheddar|mozzarella|bocconcini|parmesan|brie|camembert|"
                             r"gouda|swiss|blue vein|ricotta|fetta|feta|halloumi|haloumi|quark|cottage|labneh|tzatziki|yoghurt|yogurt|yopro|"
                             r"chobani|milk|buttermilk")),
    ("structural", W(r"flour|besan|starch|corn starch|cornflour|arrowroot|baking powder|bi-carb soda|bicarbonate of soda|cream of tartar|"
                     r"yeast|gelatine|gelatine powder|pastry|filo|wrappers?|lasagne sheets?|rice paper")),
    ("adjustable_fat", W(r"oils?|butter|ghee|margarine|cream|sour cream|cream cheese|mayonnaise|mayo|aioli|avocado|almonds?|almond meal|"
                         r"cashews?|walnuts?|pecans?|pistachios?|hazelnuts?|macadamias?|brazil nuts|pine nuts|peanuts?|peanut butter|"
                         r"nuts|seeds?|pepitas|coconut|desiccated")),
    ("adjustable_carb", W(r"rice|pasta|noodles?|bread|rolls?|bun|buns|thins?|wraps?|tortillas?|pita|pocket|naan|roti|crumpet|muffin|bagel|"
                          r"crackers?|crispbread|rice cakes?|corn cakes?|oats?|oat bran|muesli|granola|cereal|corn flakes|weet-bix|rice bubbles?|"
                          r"bran|couscous|cou cou|risoni|orzo|bulgur|barley|quinoa|buckwheat|millet|polenta|semolina|popcorn|chips|croutons|"
                          r"potato|potatoes|sweet potato|cassava|taro|dates|wheat germ|crumbs?|breadcrumbs|panko")),
    ("flavour_base", W(r"sauce|ketchup|relish|chutney|mustard|vinegar|glaze|herbs?|basil|oregano|thyme|rosemary|sage|marjoram|parsley|"
                       r"coriander|dill|mint|chives|cinnamon|nutmeg|cloves|cardamom|cardamon|cumin|turmeric|paprika|pepper|cayenne|"
                       r"chilli|chili|ginger|garlic|lemongrass|salt|sea salt|vanilla|extract|nutritional yeast|wasabi|tabasco|sriracha|"
                       r"olives?|capers?|pickles?|pickled onion|gherkin|kimchi|zest|peel|lemon juice|lime juice|juice, lemon|juice, lime|"
                       r"wine|sake|mirin|tea|tea bag|coffee|espresso|water|soda water|tonic water|kombucha|vegemite|sumac|star anise|"
                       r"furikake|nori|seaweed|tomato paste")),
    ("bulk_veg", r".*"),
]

# Names the rule would misread, or where the team's convention doesn't settle it: (role, why it needs a dietitian or None)
EXACT = [
    (r"\b(almond|oat|soy|rice) milk\b", "adjustable_protein", "plant milk: follow whatever you decide for cow's milk"),
    (r"\b(milk, full cream|buttermilk)\b", "adjustable_protein", "your existing milks are 'adjustable protein'; you said milk isn't a protein, so decide milk's role once"),
    (r"coconut yoghurt", "adjustable_fat", "coconut-based, little protein"),
    (r"konjac", "bulk_veg", "near-zero carbohydrate, so it isn't a carb serve"),
    (r"coconut water", "flavour_base", "a drink; your library treats water as flavour and juice as bulk veg"),
    (r"hummus", "adjustable_protein", "chickpea and tahini: legumes are protein in your library, but it's often used as a spread"),
    (r"banana chips", "adjustable_carb", "fried, so high in fat as well"),
    (r"tea, black, no milk|coffee", "flavour_base", None),
    (r"sugar snap peas|cauliflower rice|water chestnuts|tomato, canned|green beans?|bean sprouts?|butternut|eggplant|oyster mushroom|"
     r"swiss brown mushroom|watermelon", "bulk_veg", None),
    (r"vanilla bean|coriander seed|salsa", "flavour_base", None),
    (r"\bflour\b|besan", "structural", None),
    (r"noodles?, egg|egg noodles?", "adjustable_carb", None),
    (r"soy beans|soy/pea protein|plant mince|meat alternative", "adjustable_protein", None),
    (r"flaxseed|linseed", "adjustable_fat", None),
]

def suggest_with_note(name):
    """(role, note) — note is set when a dietitian should decide rather than just confirm."""
    n = name.lower()
    for rx, role, why in EXACT:
        if re.search(rx, n):
            return role, why
    for role, rx in RULES:
        if re.search(rx, n):
            return role, None
    return None, None

def suggest(name):
    return suggest_with_note(name)[0]
