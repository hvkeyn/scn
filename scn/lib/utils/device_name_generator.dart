import 'dart:math';

/// Utility class for generating random device names from two words
class DeviceNameGenerator {
  static final Random _random = Random();
  
  // List of adjectives (descriptive words)
  static const List<String> _adjectives = [
    'Swift', 'Bright', 'Silent', 'Quick', 'Bold', 'Calm', 'Sharp', 'Smooth',
    'Fast', 'Clear', 'Cool', 'Warm', 'Soft', 'Hard', 'Light', 'Dark',
    'Smart', 'Brave', 'Quiet', 'Loud', 'Gentle', 'Strong', 'Tiny', 'Huge',
    'Fresh', 'Old', 'New', 'Young', 'Wise', 'Kind', 'Wild', 'Tame',
    'Happy', 'Sad', 'Proud', 'Humble', 'Brave', 'Shy', 'Bold', 'Calm',
    'Eager', 'Lazy', 'Busy', 'Free', 'Rich', 'Poor', 'Fair', 'Rare',
    'Pure', 'Real', 'True', 'False', 'Safe', 'Risky', 'Easy', 'Hard',
    'Simple', 'Complex', 'Rough', 'Fine', 'Thick', 'Thin', 'Wide', 'Narrow',
    'Deep', 'Shallow', 'High', 'Low', 'Big', 'Small', 'Long', 'Short',
    'Round', 'Square', 'Flat', 'Curved', 'Straight', 'Crooked', 'Smooth', 'Rough',
  ];
  
  // List of nouns (object words)
  static const List<String> _nouns = [
    'Eagle', 'Lion', 'Tiger', 'Bear', 'Wolf', 'Fox', 'Deer', 'Hawk',
    'Falcon', 'Raven', 'Owl', 'Swan', 'Dove', 'Sparrow', 'Robin', 'Cardinal',
    'Dolphin', 'Shark', 'Whale', 'Seal', 'Otter', 'Beaver', 'Moose', 'Elk',
    'Horse', 'Stallion', 'Mare', 'Colt', 'Pony', 'Donkey', 'Mule', 'Zebra',
    'Elephant', 'Giraffe', 'Zebra', 'Rhino', 'Hippo', 'Crocodile', 'Alligator', 'Snake',
    'Dragon', 'Phoenix', 'Griffin', 'Unicorn', 'Pegasus', 'Kraken', 'Leviathan', 'Titan',
    'Star', 'Moon', 'Sun', 'Comet', 'Asteroid', 'Planet', 'Galaxy', 'Nebula',
    'Mountain', 'Valley', 'River', 'Ocean', 'Lake', 'Forest', 'Desert', 'Island',
    'Castle', 'Tower', 'Bridge', 'Temple', 'Palace', 'Fortress', 'Citadel', 'Keep',
    'Sword', 'Shield', 'Bow', 'Arrow', 'Spear', 'Axe', 'Hammer', 'Dagger',
    'Crown', 'Ring', 'Gem', 'Crystal', 'Pearl', 'Diamond', 'Ruby', 'Sapphire',
    'Flame', 'Spark', 'Ember', 'Blaze', 'Fire', 'Ice', 'Storm', 'Thunder',
    'Wind', 'Rain', 'Snow', 'Fog', 'Mist', 'Cloud', 'Lightning', 'Aurora',
    'Shadow', 'Light', 'Dawn', 'Dusk', 'Twilight', 'Midnight', 'Noon', 'Sunset',
    'Rose', 'Lily', 'Tulip', 'Daisy', 'Orchid', 'Jasmine', 'Lavender', 'Iris',
    'Oak', 'Pine', 'Maple', 'Birch', 'Cedar', 'Willow', 'Elm', 'Ash',
    'Stone', 'Rock', 'Crystal', 'Gem', 'Metal', 'Gold', 'Silver', 'Iron',
    'Wave', 'Tide', 'Current', 'Stream', 'Cascade', 'Waterfall', 'Fountain', 'Spring',
  ];
  
  /// Generates a random device name from two words (adjective + noun)
  /// Format: "Adjective Noun" (e.g., "Swift Eagle", "Bright Star")
  static String generate() {
    final adjective = _adjectives[_random.nextInt(_adjectives.length)];
    final noun = _nouns[_random.nextInt(_nouns.length)];
    return '$adjective $noun';
  }
  
  /// Generates a unique device name (same as generate, kept for compatibility)
  /// Format: "Adjective Noun" (e.g., "Swift Eagle", "Bright Star")
  static String generateUnique() {
    return generate();
  }
}

