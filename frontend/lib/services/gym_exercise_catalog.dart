import '../models/exercise_model.dart';

/// Preloaded exercise catalogue mapped directly to the openGym / ExerciseDB catalogue.
/// Provides instant access to standard gym movements with CDN video/image endpoints.
class GymExerciseCatalog {
  static const List<ExerciseModel> exercises = [
    // ================= CHEST =================
    ExerciseModel(
      id: '0025',
      name: 'barbell bench press',
      bodyPart: 'chest',
      equipment: 'barbell',
      target: 'pectorals',
      secondaryMuscles: ['triceps', 'anterior deltoids'],
      category: 'strength',
      description: 'The premier compound pressing movement for developing upper body pushing strength and chest volume.',
      instructions: [
        'Lie back on a flat bench under the rack with feet firmly planted on the floor.',
        'Grip the bar slightly wider than shoulder-width with wrists straight.',
        'Unrack the bar and stabilize it directly over your chest with arms extended.',
        'Lower the bar under control until it lightly touches your mid-chest.',
        'Press the bar back up forcefully to full arm extension without locking elbows hard.'
      ],
    ),
    ExerciseModel(
      id: '0033',
      name: 'barbell incline bench press',
      bodyPart: 'chest',
      equipment: 'barbell',
      target: 'pectorals',
      secondaryMuscles: ['anterior deltoids', 'triceps'],
      category: 'strength',
      description: 'Incline angle emphasizes the clavicular head (upper chest) and front deltoids.',
      instructions: [
        'Set an incline bench at approximately 30 to 45 degrees.',
        'Grip the barbell with a medium-width overhand grip.',
        'Lower the bar in a steady path toward your upper chest collarbone line.',
        'Drive through your palms and press back up to starting position.'
      ],
    ),
    ExerciseModel(
      id: '0289',
      name: 'dumbbell bench press',
      bodyPart: 'chest',
      equipment: 'dumbbell',
      target: 'pectorals',
      secondaryMuscles: ['triceps', 'anterior deltoids'],
      category: 'hypertrophy',
      description: 'Allows a deeper stretch at the bottom and natural wrist rotation for balanced chest development.',
      instructions: [
        'Sit on a flat bench with dumbbells resting on your thighs.',
        'Kick the weights back as you lie down, positioning them beside your chest.',
        'Press dumbbells upward until arms are extended, bringing them close together at the top.',
        'Lower with a smooth, controlled 3-second descent.'
      ],
    ),
    ExerciseModel(
      id: '0314',
      name: 'dumbbell incline bench press',
      bodyPart: 'chest',
      equipment: 'dumbbell',
      target: 'pectorals',
      secondaryMuscles: ['anterior deltoids', 'triceps'],
      category: 'hypertrophy',
      description: 'Upper chest builder using dumbbells for independent arm balance and maximum range of motion.',
      instructions: [
        'Lie on an incline bench at 30-45 degrees holding dumbbells at shoulder level.',
        'Press upward in an arc until arms are extended above your upper chest.',
        'Lower slowly, feeling the stretch across the upper pectorals.'
      ],
    ),
    ExerciseModel(
      id: '0308',
      name: 'dumbbell fly',
      bodyPart: 'chest',
      equipment: 'dumbbell',
      target: 'pectorals',
      secondaryMuscles: ['anterior deltoids'],
      category: 'hypertrophy',
      description: 'Isolated chest exercise focusing on deep pectoral stretch and adduction.',
      instructions: [
        'Lie on a flat bench holding dumbbells with palms facing each other above your chest.',
        'With a slight bend in your elbows, lower arms out to the sides in a wide hugging arc.',
        'Stop when elbows reach bench level and you feel a deep stretch in the chest.',
        'Squeeze the pectorals to bring dumbbells back to the starting point.'
      ],
    ),
    ExerciseModel(
      id: '0168',
      name: 'cable middle fly',
      bodyPart: 'chest',
      equipment: 'cable',
      target: 'pectorals',
      secondaryMuscles: ['anterior deltoids'],
      category: 'hypertrophy',
      description: 'Maintains continuous tension throughout the entire range of motion from full stretch to peak contraction.',
      instructions: [
        'Position cable pulleys at chest height and hold a handle in each hand.',
        'Step forward into a staggered stance with a slight forward torso lean.',
        'Bring hands together in front of your chest in a hugging motion.',
        'Slowly allow handles to return back until you feel a full pectoral stretch.'
      ],
    ),
    ExerciseModel(
      id: '0662',
      name: 'push-up',
      bodyPart: 'chest',
      equipment: 'body weight',
      target: 'pectorals',
      secondaryMuscles: ['triceps', 'deltoids', 'abs'],
      category: 'calisthenics',
      description: 'Classic bodyweight compound push that activates the entire chest, core, and triceps.',
      instructions: [
        'Start in a high plank position with hands slightly wider than shoulder-width.',
        'Keep your body in a rigid straight line from head to heels.',
        'Lower chest toward the ground until elbows are bent at 90 degrees.',
        'Push the floor away to return to the starting plank.'
      ],
    ),

    // ================= BACK =================
    ExerciseModel(
      id: '0027',
      name: 'barbell deadlift',
      bodyPart: 'back',
      equipment: 'barbell',
      target: 'glutes',
      secondaryMuscles: ['hamstrings', 'erector spinae', 'lats', 'traps', 'forearms'],
      category: 'strength',
      description: 'The king of posterior chain exercises, building full-body power, back thickness, and hip hinge strength.',
      instructions: [
        'Stand with feet hip-width apart, barbell over mid-foot.',
        'Hinge at hips and grip the bar just outside your shins.',
        'Flatten back, engage lats, take a deep breath into the abdomen.',
        'Drive through the floor with your legs, keeping the bar close to your shins.',
        'Stand tall at the top without hyperextending your lower back, then lower with control.'
      ],
    ),
    ExerciseModel(
      id: '0022',
      name: 'barbell bent over row',
      bodyPart: 'back',
      equipment: 'barbell',
      target: 'upper back',
      secondaryMuscles: ['lats', 'biceps', 'rear deltoids'],
      category: 'strength',
      description: 'Fundamental horizontal pull for back density, lat thickness, and spinal stability.',
      instructions: [
        'Hold barbell with an overhand grip and hinge forward at hips to roughly a 45-degree angle.',
        'Keep spine neutral and knees slightly bent.',
        'Pull the barbell towards your lower ribcage / belly button, driving with your elbows.',
        'Squeeze your shoulder blades together at the top, then lower smoothly.'
      ],
    ),
    ExerciseModel(
      id: '0150',
      name: 'cable lat pulldown',
      bodyPart: 'back',
      equipment: 'cable',
      target: 'lats',
      secondaryMuscles: ['biceps', 'middle back'],
      category: 'strength',
      description: 'Vertical pull targeting lat width and upper back development.',
      instructions: [
        'Sit at the lat pulldown station with thighs secured under pads.',
        'Grasp the wide bar with an overhand grip slightly wider than shoulder-width.',
        'Lean back slightly (10-15 degrees) and pull the bar down to your upper collarbone.',
        'Control the bar as it rises back up to full overhead stretch.'
      ],
    ),
    ExerciseModel(
      id: '0198',
      name: 'cable seated row',
      bodyPart: 'back',
      equipment: 'cable',
      target: 'upper back',
      secondaryMuscles: ['lats', 'biceps', 'rhomboids'],
      category: 'hypertrophy',
      description: 'Controlled cable pull focusing on mid-back thickness, rhomboids, and lower traps.',
      instructions: [
        'Sit with feet on the footplates, knees slightly bent.',
        'Grip the close-grip V-bar handle and sit up tall with back straight.',
        'Pull the handle into your abdomen while keeping elbows tucked.',
        'Extend arms forward allowing your shoulder blades to spread for a full stretch.'
      ],
    ),
    ExerciseModel(
      id: '0652',
      name: 'pull-up',
      bodyPart: 'back',
      equipment: 'body weight',
      target: 'lats',
      secondaryMuscles: ['biceps', 'forearms', 'upper back'],
      category: 'calisthenics',
      description: 'Ultimate bodyweight vertical pulling movement for upper body functional strength.',
      instructions: [
        'Hang from a pull-up bar with an overhand grip slightly wider than shoulders.',
        'Retract your scapula and pull your body up until your chin clears the bar.',
        'Lower yourself under control back to a dead hang.'
      ],
    ),

    // ================= SHOULDERS =================
    ExerciseModel(
      id: '0070',
      name: 'barbell overhead press',
      bodyPart: 'shoulders',
      equipment: 'barbell',
      target: 'deltoids',
      secondaryMuscles: ['triceps', 'traps', 'upper chest'],
      category: 'strength',
      description: 'Standing overhead press for shoulder power, overhead stability, and core rigidity.',
      instructions: [
        'Hold the bar at collarbone height with elbows slightly in front of the bar.',
        'Brace your glutes and core tightly.',
        'Press the bar straight upward, moving your head slightly back until the bar clears your forehead.',
        'Lock out overhead with bar directly aligned with your spine.'
      ],
    ),
    ExerciseModel(
      id: '0355',
      name: 'dumbbell shoulder press',
      bodyPart: 'shoulders',
      equipment: 'dumbbell',
      target: 'deltoids',
      secondaryMuscles: ['triceps', 'traps'],
      category: 'hypertrophy',
      description: 'Seated or standing press providing independent overhead shoulder development.',
      instructions: [
        'Sit on an upright bench with dumbbells at ear height, palms facing forward.',
        'Press weights directly overhead until arms are extended.',
        'Lower slowly back to ear level to maintain continuous shoulder tension.'
      ],
    ),
    ExerciseModel(
      id: '0334',
      name: 'dumbbell lateral raise',
      bodyPart: 'shoulders',
      equipment: 'dumbbell',
      target: 'deltoids',
      secondaryMuscles: ['traps'],
      category: 'hypertrophy',
      description: 'The golden exercise for building wider shoulders by isolating the lateral deltoid head.',
      instructions: [
        'Stand tall with dumbbells resting at your sides, palms facing inward.',
        'With a slight bend in your elbows, raise weights out to the sides until parallel to the floor.',
        'Lead with your elbows and avoid swinging your torso.',
        'Lower slowly under control.'
      ],
    ),
    ExerciseModel(
      id: '0160',
      name: 'cable face pull',
      bodyPart: 'shoulders',
      equipment: 'cable',
      target: 'deltoids',
      secondaryMuscles: ['rotator cuff', 'upper back', 'traps'],
      category: 'hypertrophy',
      description: 'Essential posture and shoulder health movement targeting rear delts and external rotators.',
      instructions: [
        'Attach a rope to a cable pulley set at eye level.',
        'Grip the rope ends with thumbs pointing backward.',
        'Pull the rope toward your face, flaring elbows out and pulling hands apart.',
        'Squeeze the rear shoulders for a one-second pause before returning.'
      ],
    ),

    // ================= LEGS =================
    ExerciseModel(
      id: '0043',
      name: 'barbell full squat',
      bodyPart: 'upper legs',
      equipment: 'barbell',
      target: 'quads',
      secondaryMuscles: ['glutes', 'hamstrings', 'calves', 'erector spinae'],
      category: 'strength',
      description: 'The definitive lower body strength builder targeting quadriceps, hips, and core stability.',
      instructions: [
        'Rest the barbell securely across your upper traps / rear delts.',
        'Step out with feet shoulder-width apart, toes angled slightly outward.',
        'Inhale, brace your core, and descend by breaking at the hips and knees simultaneously.',
        'Descend until thighs are at least parallel to the floor.',
        'Drive through mid-foot to stand back up to starting position.'
      ],
    ),
    ExerciseModel(
      id: '0585',
      name: 'leg press',
      bodyPart: 'upper legs',
      equipment: 'machine',
      target: 'quads',
      secondaryMuscles: ['glutes', 'hamstrings'],
      category: 'hypertrophy',
      description: 'Heavy quad overloading without spinal compression.',
      instructions: [
        'Sit firmly in the leg press seat with feet shoulder-width on the platform.',
        'Release safety bars and lower the sled until knees are at 90 degrees.',
        'Press through your heels and mid-foot to push the platform back up without locking knees.'
      ],
    ),
    ExerciseModel(
      id: '0583',
      name: 'leg extension',
      bodyPart: 'upper legs',
      equipment: 'machine',
      target: 'quads',
      secondaryMuscles: [],
      category: 'hypertrophy',
      description: 'Direct quadriceps isolation for peak contraction and knee tendon strength.',
      instructions: [
        'Adjust the pad so it rests on top of your lower shins just above ankles.',
        'Extend your legs fully upward, pausing briefly at the top to squeeze quads.',
        'Lower the weight with a controlled 3-second descent.'
      ],
    ),
    ExerciseModel(
      id: '0584',
      name: 'lying leg curl',
      bodyPart: 'upper legs',
      equipment: 'machine',
      target: 'hamstrings',
      secondaryMuscles: ['calves'],
      category: 'hypertrophy',
      description: 'Isolates the knee flexion function of the hamstrings for balanced leg development.',
      instructions: [
        'Lie face down on the machine with roller pad against the back of your ankles.',
        'Keep hips pressed flat against the bench.',
        'Curl your heels upward toward your glutes as far as possible.',
        'Hold for a brief contraction, then lower under steady resistance.'
      ],
    ),
    ExerciseModel(
      id: '0085',
      name: 'barbell romanian deadlift',
      bodyPart: 'upper legs',
      equipment: 'barbell',
      target: 'hamstrings',
      secondaryMuscles: ['glutes', 'lower back'],
      category: 'strength',
      description: 'Pure hip-hinge movement that provides deep hamstring elongation and glute strength.',
      instructions: [
        'Stand holding barbell at thighs with shoulders back.',
        'Keeping a slight knee bend, push your hips backward as if touching a wall behind you.',
        'Lower the bar along your thighs until you feel a full stretch in hamstrings.',
        'Drive hips forward to return to standing.'
      ],
    ),
    ExerciseModel(
      id: '0016',
      name: 'barbell hip thrust',
      bodyPart: 'upper legs',
      equipment: 'barbell',
      target: 'glutes',
      secondaryMuscles: ['hamstrings', 'quads'],
      category: 'strength',
      description: 'Maximum horizontal glute recruitment with high loading capability.',
      instructions: [
        'Sit on the ground with upper back against a bench and padded barbell over your hips.',
        'Plant feet firmly flat on the floor at shoulder-width.',
        'Drive through your heels to extend your hips upward until thighs and torso align horizontally.',
        'Squeeze glutes hard at the top, then lower with control.'
      ],
    ),

    // ================= ARMS (BICEPS & TRICEPS) =================
    ExerciseModel(
      id: '0031',
      name: 'barbell curl',
      bodyPart: 'upper arms',
      equipment: 'barbell',
      target: 'biceps',
      secondaryMuscles: ['forearms'],
      category: 'strength',
      description: 'Foundational mass builder for the biceps brachii.',
      instructions: [
        'Stand tall with an underhand shoulder-width grip on the barbell.',
        'Keep elbows pinned near your ribs.',
        'Curl the bar upward toward chest level by flexing the biceps.',
        'Squeeze at the peak, then lower under a slow, controlled negative.'
      ],
    ),
    ExerciseModel(
      id: '0313',
      name: 'dumbbell hammer curl',
      bodyPart: 'upper arms',
      equipment: 'dumbbell',
      target: 'biceps',
      secondaryMuscles: ['brachialis', 'forearms'],
      category: 'hypertrophy',
      description: 'Neutral grip curl targeting the brachialis and brachioradialis for thicker upper arms and forearms.',
      instructions: [
        'Hold dumbbells at sides with palms facing inward towards your body.',
        'Without rotating wrists, curl weights up toward shoulder height.',
        'Lower slowly along the same path.'
      ],
    ),
    ExerciseModel(
      id: '0201',
      name: 'cable triceps pushdown',
      bodyPart: 'upper arms',
      equipment: 'cable',
      target: 'triceps',
      secondaryMuscles: [],
      category: 'hypertrophy',
      description: 'High-isolation triceps exercise targeting the lateral and medial heads with constant cable tension.',
      instructions: [
        'Attach a straight bar or rope to a high pulley.',
        'Stand with a slight forward lean and pin elbows to your sides.',
        'Push the attachment down until arms are fully locked out at the bottom.',
        'Slowly allow forearms to return to parallel without letting elbows move forward.'
      ],
    ),
    ExerciseModel(
      id: '0038',
      name: 'barbell skull crusher',
      bodyPart: 'upper arms',
      equipment: 'barbell',
      target: 'triceps',
      secondaryMuscles: ['forearms'],
      category: 'hypertrophy',
      description: 'Lying triceps extension emphasizing the long head of the triceps.',
      instructions: [
        'Lie on a flat bench holding an EZ-bar or barbell directly above your chest.',
        'Keeping upper arms perpendicular to the floor, bend elbows to lower bar toward your forehead.',
        'Extend elbows forcefully to return to lockout.'
      ],
    ),

    // ================= CORE & ABS =================
    ExerciseModel(
      id: '0001',
      name: '3/4 sit-up',
      bodyPart: 'waist',
      equipment: 'body weight',
      target: 'abs',
      secondaryMuscles: ['hip flexors'],
      category: 'calisthenics',
      description: 'Continuous-tension abdominal crunch keeping active contraction throughout.',
      instructions: [
        'Lie flat on your back with knees bent and feet flat on the ground.',
        'Place hands behind head or across chest.',
        'Curl upper body up to approximately 45 degrees, contracting abdominals.',
        'Lower under control without resting flat between reps.'
      ],
    ),
    ExerciseModel(
      id: '0659',
      name: 'plank',
      bodyPart: 'waist',
      equipment: 'body weight',
      target: 'abs',
      secondaryMuscles: ['glutes', 'shoulders', 'lower back'],
      category: 'calisthenics',
      description: 'Isometric core stability pillar strengthening the transverse abdominis and lower back.',
      instructions: [
        'Rest on forearms and toes with elbows aligned directly under shoulders.',
        'Keep body in a perfectly straight line from head to heels.',
        'Brace your core, squeeze glutes, and hold without sagging hips.'
      ],
    ),
    ExerciseModel(
      id: '0468',
      name: 'hanging leg raise',
      bodyPart: 'waist',
      equipment: 'body weight',
      target: 'abs',
      secondaryMuscles: ['hip flexors', 'grip / forearms'],
      category: 'calisthenics',
      description: 'Hanging core movement targeting lower abdominals and hip flexors.',
      instructions: [
        'Hang from a pull-up bar with an overhand grip.',
        'Without swinging, raise legs straight out in front until parallel to the floor (or higher).',
        'Lower slowly under control to prevent momentum.'
      ],
    ),
  ];

  /// Find exercise by ID (e.g. "0025")
  static ExerciseModel? findById(String id) {
    final searchId = id.padLeft(4, '0');
    try {
      return exercises.firstWhere((e) => e.formattedId == searchId);
    } catch (_) {
      return null;
    }
  }

  /// Filter exercises by body part (e.g. "chest", "back", "upper legs", "shoulders", "upper arms", "waist")
  static List<ExerciseModel> filterByBodyPart(String bodyPart) {
    if (bodyPart.isEmpty || bodyPart.toLowerCase() == 'all') {
      return exercises;
    }
    return exercises
        .where((e) => e.bodyPart.toLowerCase() == bodyPart.toLowerCase())
        .toList();
  }

  /// Filter exercises by equipment (e.g. "barbell", "dumbbell", "cable", "body weight", "machine")
  static List<ExerciseModel> filterByEquipment(String equipment) {
    if (equipment.isEmpty || equipment.toLowerCase() == 'all') {
      return exercises;
    }
    return exercises
        .where((e) => e.equipment.toLowerCase() == equipment.toLowerCase())
        .toList();
  }

  /// Search exercises by name or target muscle
  static List<ExerciseModel> search(String query) {
    if (query.trim().isEmpty) return exercises;
    final q = query.trim().toLowerCase();
    return exercises.where((e) {
      return e.name.toLowerCase().contains(q) ||
          e.target.toLowerCase().contains(q) ||
          e.bodyPart.toLowerCase().contains(q) ||
          e.equipment.toLowerCase().contains(q);
    }).toList();
  }

  /// List of unique body parts for UI filter chips
  static List<String> get allBodyParts => [
        'All',
        'Chest',
        'Back',
        'Shoulders',
        'Upper Legs',
        'Upper Arms',
        'Waist',
      ];

  /// List of unique equipment types for UI filter chips
  static List<String> get allEquipment => [
        'All',
        'Barbell',
        'Dumbbell',
        'Cable',
        'Body Weight',
        'Machine',
      ];
}
