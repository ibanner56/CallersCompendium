// Shipped glossary text for the contra taxonomy's figures (issue #695).
//
// Written in our own words. The facts were checked against two references,
// neither of which is quoted:
// - The Caller's Box glossary ("TCB"),
//   https://www.ibiblio.org/contradance/thecallersbox/Glossary.htm, fetched
//   2026-10-14.
// - The glossary of Larry Jennings's "Give and Take" (pp. 11-13), a published
//   work that may inform these definitions but must never be used verbatim.
// Where a reference and the taxonomy disagree, the text matches the taxonomy
// (it has to describe the figure the app actually models) and a "Note:"
// comment records the disagreement.
//
// Role words are written as the canonical tokens role1/role1s/role2/role2s,
// which the dialect renderer turns into the user's terms at display time.
// figure_glossary_test.dart holds every entry to that rule.

import 'figure_glossary.dart' show FigureDefinition;

/// The shipped definitions for [contraTaxonomy]'s figures, keyed by move or
/// alias id. Every glossary figure has an entry; figure_glossary_test.dart
/// fails the build when one is missing.
const Map<String, FigureDefinition> contraFigureDefinitions = {
  // TCB "Swing".
  'swing': FigureDefinition(
    definition:
        'Two dancers take a close ballroom-style hold and turn clockwise together around a shared center.',
    description:
        'Dancers stand slightly offset, right side to right side, and turn with a walking step or a buzz step. A plain swing usually takes 8 beats; one that starts with a balance or a meltdown fills 16. It ends with the role1 on the left and the role2 on the right, facing wherever the next figure needs, usually across the set.',
  ),
  // TCB "Balance"; Jennings EN1 (which hands are held varies by community).
  'balance': FigureDefinition(
    definition:
        'Dancers step toward someone and back again, in place, without traveling.',
    description:
        'A balance takes 4 beats of footwork, often a step in and a step back. Communities differ on whether hands are held and which ones; the figure can name a hand. It usually comes right before a swing, a turn, or a figure that trades places.',
  ),
  // TCB "Balance ring".
  'balance_the_ring': FigureDefinition(
    definition:
        'A ring of four, hands joined, steps in toward the center and back out together.',
    description:
        'The ring stays where it is while everyone balances in and out. It takes 4 beats and often comes right before a petronella, a swing, or a circle.',
  ),
  // TCB "Allemande".
  'allemande': FigureDefinition(
    definition:
        'Two dancers join right or left hands and walk around each other, turning by the joined hands.',
    description:
        'Hands are held in a firm, palm-to-palm grip at about shoulder height, with a little weight given so the turn has energy. The figure names the hand and how far to turn, such as once around or one and a half. Once around usually takes 8 beats.',
  ),
  // TCB "Two-hand turn" (clockwise by default).
  'two_hand_turn': FigureDefinition(
    definition:
        'Two dancers face each other, take both hands, and walk around each other.',
    description:
        'It sits somewhere between an allemande and a swing, and turns clockwise unless the dance says otherwise. The figure names how far to turn; once around usually takes 8 beats, most often with partners.',
  ),
  // TCB "Do-si-do"; Jennings "REVERSE" (a reverse dosido is the seesaw).
  'do_si_do': FigureDefinition(
    definition:
        'Two dancers face each other, pass right shoulders, go back to back, and return to place.',
    description:
        'Dancers keep facing the same way throughout: forward, a step to the side, then backward to place, without taking hands. Once around usually takes 8 beats; the figure can name a longer distance, such as one and a half. The left-shoulder version is the seesaw.',
  ),
  // TCB "Box the gnat", "Twirl to swap"; Jennings "TWIRL TO SWAP".
  'box_the_gnat': FigureDefinition(
    definition:
        'Two dancers facing each other join right hands and trade places, one turning under the raised arch.',
    description:
        'Usually the role2 turns under the joined hands while the role1 walks around them, and the pair ends facing each other in swapped places. It takes 4 beats, or 8 when it starts with a balance. The left-hand version is swat the flea.',
  ),
  // TCB "Circulate"; Jennings "ROTATE THE FOURSOME" (the same idea in long
  // waves); contra_taxonomy.dart `box_circulate` (who default role2s, hand
  // default right, balance flag, 4 beats).
  // Note: TCB describes this in long waves, with the dancers facing out
  // looping and the dancers facing in crossing; the app records who crosses
  // and the looping hand, so the text matches that model.
  'box_circulate': FigureDefinition(
    definition:
        'In a group of four in waves, each dancer moves on one place: some cross the set while the others loop around.',
    description:
        'Usually danced from long waves. The named dancers, often the role2s, walk straight across the set, while the other two loop around into the place beside them by the named hand. Everyone ends in new waves. It takes 4 beats, or 8 with a balance first.',
  ),
  // TCB "Shoulder round"; Jennings's entry for the same figure (clockwise
  // unless reversed).
  'shoulder_round': FigureDefinition(
    definition:
        'Two dancers walk around each other face to face, without touching, keeping eye contact.',
    description:
        'Think of it as a hands-free allemande. A right shoulder round turns clockwise and a left shoulder round turns counterclockwise. The figure names the shoulder and how far to go; once around usually takes 8 beats, and when a swing comes next the distance is often left open.',
  ),
  // TCB "Petronella turn".
  'petronella': FigureDefinition(
    definition:
        'From a ring of four, everyone lets go and moves one place to the right, spinning clockwise as they go.',
    description:
        'Each dancer travels one position counterclockwise around the ring while turning clockwise, ending facing the center. Many communities add a clap at the end. It takes 4 beats on its own or 8 with the balance the ring that usually comes first, and it is often repeated.',
  ),
  // TCB "Long lines, go forward and back", "Forward and back".
  'long_lines': FigureDefinition(
    definition:
        'Dancers in lines along each side of the set join hands, walk forward toward the other line, and back.',
    description:
        'Forward and back together usually takes 8 beats: 4 in and 4 out. Some dances go forward only, for 4 beats, and do something else on the way back, such as a roll away.',
  ),
  // TCB "Pass through".
  'pass_through': FigureDefinition(
    definition:
        'Dancers facing each other walk forward, passing right shoulders, to take each other\'s places.',
    description:
        'No hands are taken. It usually takes 2 beats and is most often done along the set to meet new neighbors; the figure names the direction when it is across or on a diagonal, and a left-shoulder pass when that is wanted.',
  ),
  // TCB "Right and left through".
  'right_left_through': FigureDefinition(
    definition:
        'Two couples facing each other pass through, then each couple courtesy turns to face back in.',
    description:
        'Dancers pass right shoulders with the person opposite (some communities pull by right hands instead), and the two dancers who crossed side by side turn as a couple. It usually takes 8 beats and goes across the set unless a diagonal is named.',
  ),
  // TCB's chain entries (the role2s' chain and its role1s' mirror).
  'chain': FigureDefinition(
    definition:
        'Two dancers of the same role cross the set, pulling by one hand, and are each turned by the dancer waiting there.',
    description:
        'Most often the role2s chain: they pull by right hands, veer a little to the right, and each is received by the role1 on the far side with a courtesy turn so the couple faces back in. When the role1s chain, it is the mirror image, by the left hand. It usually takes 8 beats, across the set or on a named diagonal.',
  ),
  // TCB "Courtesy turn" and its role1s' chain entry. The usual rotation
  // is counterclockwise; clockwise is the mirrored turn, chiefly after a
  // role1s' chain (maintainer decision on #695; the taxonomy default changes
  // to match in #1764). The text says "usually" so it holds on either side
  // of that change.
  'courtesy_turn': FigureDefinition(
    definition:
        'Two dancers side by side wheel around together, as a unit, to face the opposite way.',
    description:
        'The usual hold joins left hands in front, with the role1\'s right hand at the role2\'s back. They usually pivot counterclockwise around a point between them, the left-hand dancer stepping backward and the right-hand dancer forward. After a role1s\' chain the turn is mirrored and goes clockwise. It most often finishes a chain, a right and left through, or a promenade across, and usually takes 4 beats.',
  ),
  // TCB "Promenade".
  'promenade': FigureDefinition(
    definition:
        'Two dancers walk side by side, facing the same way with hands joined, traveling together to a new place.',
    description:
        'Usually right hands are joined with right and left with left, the role1 on the left. A promenade across the set ends with a turn to face back in and usually takes 8 beats. The figure can name where the pair travels, across the set unless stated. In a single-file promenade, dancers walk one behind another.',
  ),
  // TCB "Roll away", "Long lines, go forward and back with rollaway";
  // Jennings "ROLLAWAY", "HALF SASHAY".
  'roll_away': FigureDefinition(
    definition:
        'Two dancers side by side trade places: one sidesteps across while gently guiding the other to roll across in front of them.',
    description:
        'The rolled dancer turns once around as they cross, never turning their back on the other. Both end facing the same way as they started. Many dances call it a roll away with a half sashay. The figure names who guides and who is rolled. It usually takes 4 beats.',
  ),
  // TCB "Butterfly whirl".
  'butterfly_whirl': FigureDefinition(
    definition:
        'Two dancers side by side, arms around each other\'s backs, turn together around a point between them.',
    description:
        'Both face the same way; one walks forward while the other backs up. It almost always comes right after a star promenade and usually takes 4 beats. The figure names the pair and whether they turn clockwise or counterclockwise.',
  ),
  // TCB "Arch, dive".
  'arch_and_dive': FigureDefinition(
    definition:
        'One couple raises joined hands to make an arch while the couple facing them ducks underneath, and they trade places.',
    description:
        'Everyone walks forward. The named couple, often the ones, makes the arch. It usually takes 4 beats.',
  ),
  // TCB "California twirl", "Twirl to swap"; Jennings "TWIRL TO SWAP"
  // (role2 turns counterclockwise, role1 clockwise).
  'california_twirl': FigureDefinition(
    definition:
        'Two dancers side by side raise their joined hands and trade places, the role2 turning under, to face the other way.',
    description:
        'The role1\'s right hand holds the role2\'s left. The role2 turns counterclockwise under the arch while the role1 walks around clockwise, so the pair ends facing the opposite direction. It usually takes 4 beats, most often with partners.',
  ),
  // TCB "Star through", "Twirl to swap"; Jennings "TWIRL TO SWAP".
  'star_through': FigureDefinition(
    definition:
        'Two dancers facing each other join the role1\'s right hand to the role2\'s left and turn to stand side by side, the role2 turning under.',
    description:
        'It is the face-to-face cousin of the California twirl: each dancer makes a quarter turn, the role2 passing under the raised arch, and the pair ends side by side facing the same way. It usually takes 4 beats.',
  ),
  // TCB "Turn as couples".
  'turn_as_couples': FigureDefinition(
    definition:
        'Two dancers side by side turn around together to face the opposite direction.',
    description:
        'The dancers choose the mechanics: a courtesy turn, a California twirl, or a hand cast all work. It is the usual way for a line of four to change direction, most often at the end of a walk down the hall. It usually takes 4 beats.',
  ),
  // No TCB entry; contra_taxonomy.dart `stand_still`.
  'stand_still': FigureDefinition(
    definition: 'Dancers wait in place for the stated number of beats.',
    description:
        'Used when some dancers rest while others move, or to fill out a phrase. Any length is possible; the figure records the number of beats.',
  ),
  // TCB "Shift"; Jennings "SHIFT" (one station by default).
  'slide_along_set': FigureDefinition(
    definition:
        'Couples on the side of the set sidestep left or right until they face the next couple.',
    description:
        'It usually moves dancers one place and takes 2 beats. It is common at the start of Becket formation dances, usually just before a circle with the new couple. The figure names which way to slide.',
  ),
  // TCB "Mad robin".
  'mad_robin': FigureDefinition(
    definition:
        'A sideways dosido around the dancer beside you, keeping eye contact with someone across the set.',
    description:
        'Dancers keep eye contact across the set while they slide around their neighbor or partner, one passing in front and the other behind, then back to place. In a clockwise mad robin the dancer on the left passes in front first; counterclockwise, the dancer on the right. The figure names who goes in front first and whom you travel around. Once around takes 6 to 8 beats.',
  ),
  // TCB "Revolving door".
  'revolving_door': FigureDefinition(
    definition:
        'Two dancers carry their partners across the set in a star promenade, drop them off, and turn on to someone new.',
    description:
        'Usually the role2s join right hands or arms and promenade to the far side with the role1 they just swung, let go of them there, and turn halfway by the right to meet the other role1, often for a swing. The figure names who joins in the center, which hand, and who is carried. It usually takes 8 beats.',
  ),
  // TCB "Star promenade".
  'star_promenade': FigureDefinition(
    definition:
        'Two couples walk forward together, the center dancers holding hands across the middle and arms around the dancer beside them.',
    description:
        'Each couple stands side by side with arms around each other\'s backs, while one dancer from each couple joins hands in the center. The whole shape turns forward, usually halfway, to the other side of the set. It usually takes 4 beats and a butterfly whirl almost always comes next.',
  ),
  // TCB "Orbit".
  'orbit': FigureDefinition(
    definition:
        'Two dancers walk around the outside of two others, usually while those two turn in the middle.',
    description:
        'An orbit is usually danced at the same time as an allemande: the center pair turns while the outside pair walks a wider circle around them. The figure names who orbits, the direction, and how far, usually half way. It usually takes 8 beats.',
  ),
  // TCB "Gate".
  'gate': FigureDefinition(
    definition:
        'Two dancers side by side, holding near hands, pivot like a swinging gate: one backs up while the other walks forward.',
    description:
        'The pair rotates around the point between them. The figure can name the pair, the direction (including a mirror gate, where two pairs turn opposite ways), how far, and which way they end up facing. It often turns dancers to face up or down the set; 8 beats is typical, though shorter gates are common.',
  ),
  // TCB "Give and take"; Jennings "GIVE-AND-TAKE" (default side);
  // contra_taxonomy.dart `give_and_take` (who = the role the pair ends beside,
  // default role1s; give flag; 8 beats). The 4-8 beat range, depending on
  // the dance and its phrasing, is the maintainer's wording.
  'give_and_take': FigureDefinition(
    definition:
        'Facing couples step toward each other, and the named dancers draw another dancer, usually their partner, back to their own side.',
    description:
        'Everyone takes a couple of steps in; then the named dancers, by default the role1s, take hands with the dancer they are taking, usually their partner, and back up, bringing that dancer to their side of the set, ready to swing. It takes 4 to 8 beats, depending on the dance and its phrasing. With take only, nobody steps in first.',
  ),
  // TCB "Pull by".
  'pull_by': FigureDefinition(
    definition:
        'Two dancers take hands and pull past each other, letting go as they pass and continuing on.',
    description:
        'It is usually done by the right hand. A pull by takes 2 beats, or 4 with a balance first. The figure can name the dancers, often neighbors, or the direction, such as along or across the set.',
  ),
  // TCB "Cross trail through".
  'cross_trails': FigureDefinition(
    definition:
        'Two quick passes without hands: first with one dancer across the set, then with another along it.',
    description:
        'Typically dancers pass partners by the right shoulder across the set, then turn to pass neighbors by the left shoulder along it, or the reverse. The figure names both pairs and the first pass\'s direction and shoulder. It usually takes 4 beats.',
  ),
  // TCB "Line of four, go down/up the hall".
  'down_the_hall': FigureDefinition(
    definition:
        'Dancers in lines of four, facing down the set, walk down the hall together.',
    description:
        'Usually everyone travels, hands joined in lines, for about 8 beats, then turns to come back. The figure can say who moves, whether dancers face forward or back up, and how they turn around at the end: as couples, alone, bending into a ring, and other endings.',
  ),
  // TCB "Line of four, go down/up the hall", "Bend the line".
  'up_the_hall': FigureDefinition(
    definition:
        'Dancers in lines of four, facing up the set, walk back up the hall together.',
    description:
        'Usually the return trip after a walk down the hall, taking about 8 beats. The figure can say who moves, which way they face, and how the lines finish, most often by bending into a ring of four.',
  ),
  // TCB "Weave the line" (zig zag is the preferred name for it, per the
  // maintainer); contra_taxonomy.dart `zig_zag` (who default partners, slide
  // default left, ender, 6 beats).
  'zig_zag': FigureDefinition(
    definition:
        'Couples facing along the set weave past each other on alternating diagonals, like a hey danced in pairs.',
    description:
        'Holding near hands with the dancer beside them, each pair steps forward and to one side, usually the left, then forward and to the other, sliding past the oncoming couple until everyone has moved on to face someone new. It usually takes 6 beats and can finish by forming a ring or with the trailing dancers catching hands.',
  ),
  // TCB "Slice".
  'slice': FigureDefinition(
    definition:
        'Couples on the side step forward on a diagonal toward the next couple, then fall back straight across.',
    description:
        'It is a forward and back with a twist: four steps in on the named diagonal, a small pivot to face straight across, and four steps back, which shifts everyone one place along the set. A slice by one dancer shifts by a single dancer instead. With a return it usually takes 8 beats; without one, 4.',
  ),
  // TCB "Contra corners".
  'contra_corners': FigureDefinition(
    definition:
        'The active dancers turn each other, then each of their two corners in turn, in a chain of four allemandes.',
    description:
        'Facing across, your first corner is on your right diagonal and your second on your left. The actives turn each other by the right, a corner by the left, each other again, and the other corner by the left. It usually takes 16 beats and often ends with a swing in the center; a dance can note its own variation.',
  ),
  // TCB "Turn alone".
  'turn_alone': FigureDefinition(
    definition:
        'Each dancer lets go and turns around individually to face the opposite direction.',
    description:
        'Which way to turn depends on the figures around it. It is most often used at the end of a walk down the hall, takes up to about 4 beats, and a dance can add a note about how to turn.',
  ),
  // TCB "Figure eight", "Half figure eight".
  'figure_8': FigureDefinition(
    definition:
        'A couple weaves a figure-eight path around two other dancers, crossing between them.',
    description:
        'In a half figure 8, the couple crosses on a diagonal between the other two dancers and loops around one of them, ending on the opposite side, usually in 8 beats; a full figure 8 repeats that back home, in 16. One dancer crosses first, usually the role2. The figure can say whether the couple goes up, down, or across the set.',
  ),
  // TCB "Poussette" (and "Draw poussette" for contrast).
  // Note: the taxonomy also records who pulls back first, which TCB's
  // poussette does not mention; the text keeps that detail as the app's.
  'poussette': FigureDefinition(
    definition:
        'Two dancers holding both hands travel as a pair around another pair without rotating.',
    description:
        'The pair never rotates: one dancer moves forward while the other backs up, then they shift sideways around the other couple. A half poussette swaps the pairs\' places in about 6 to 8 beats, and a full one brings them home. The figure names who backs up first, who they hold, and the direction.',
  ),
  // TCB "Slide right/left".
  'rory_o_more': FigureDefinition(
    definition:
        'Dancers in a wave balance, then let go and slide sideways past one dancer into the next place.',
    description:
        'Usually everyone balances right and left, then slides right with a clockwise spin, or left with a counterclockwise one, ending in a new wave facing the same way. With the balance it usually takes 8 beats; the slide alone takes 4. The figure names the direction and, when not everyone, who dances it.',
  ),
  // TCB "Circle left/right".
  'circle': FigureDefinition(
    definition:
        'Dancers join hands in a ring and walk around together, to the left or the right.',
    description:
        'Circling left travels clockwise and circling right counterclockwise. The figure counts how far to go in places: four places brings a ring of four home, usually in 8 beats, and three places is a common shorter circle. In a single-file circle dancers walk one behind another instead of holding hands.',
  ),
  // TCB "Star", "Hands-across star".
  'star': FigureDefinition(
    definition:
        'Dancers put the same hand into the center and walk around together, usually four dancers.',
    description:
        'A right-hand star travels clockwise and a left-hand star counterclockwise. The figure counts how far to go in places; four places brings everyone home, usually in 8 beats. It can name the grip: in many communities each dancer holds the wrist ahead, while in a hands-across star opposite dancers take hands.',
  ),
  // TCB "Facing star".
  'facing_star': FigureDefinition(
    definition:
        'A star in which two of the four dancers walk backward, so dancers face each other as it turns.',
    description:
        'Each diagonal pair puts a different hand in the middle, one pair right and the other left, and dancers often hold their free hand with the person in front of them. Two diagonally opposite dancers back up while the other two walk forward. It usually travels 3 places in about 8 beats.',
  ),
  // TCB "Square through".
  'square_through': FigureDefinition(
    definition:
        'Dancers pull by the person they face, turn to the next, and pull by with the other hand, around a square of four.',
    description:
        'Typically partners pull by right hands, turn a quarter, and neighbors pull by left hands; square through four repeats both. The figure names who goes first, the starting hand, whether each pull starts with a balance, and the number of pulls, usually 2 or 4. With balances, square through four usually takes 16 beats.',
  ),
  // TCB "Pass".
  'pass_by': FigureDefinition(
    definition:
        'Two dancers walk past each other by a shoulder, usually the right, without taking hands.',
    description:
        'It usually takes 2 beats and is often one step of a larger weaving pattern. The figure names the dancers and the shoulder.',
  ),
  // TCB "Hey", "Ricochet hey"; Jennings EN5 (the named shoulder is the one
  // passed in the center).
  'hey': FigureDefinition(
    definition:
        'Four dancers weave past one another along a figure-eight path, alternating shoulders.',
    description:
        'Two dancers pass in the center by the named shoulder while the other two loop in from the ends, then everyone passes the next dancer by the other shoulder, and the pattern repeats. A half hey brings everyone to the far end, usually in 8 beats; a full hey returns them home, in 16. The figure names who passes first and by which shoulder; a partial hey runs until a named pair meets, and in a ricochet hey a pair meeting in the center rebounds back to its own side instead of passing.',
  ),
  // TCB "Circular hey": the corpus writes it as "square through N without
  // hands" (e.g. dances 20273 and 527, three changes in 8 beats). The beat
  // counts per number of changes are the app's own choice (taxonomy v36),
  // confirmed by the maintainer.
  'circular_hey': FigureDefinition(
    definition:
        'A square through without hands: four dancers weave around their ring, passing alternate shoulders.',
    description:
        'Sometimes called a square hey. The named dancers pass first, usually neighbors by the right shoulder, then each dancer turns to pass the next person by the other shoulder. The figure counts the changes: four brings everyone home, in about 12 beats, and fewer changes take less time.',
  ),
  // TCB "Dolphin hey".
  'dolphin_hey': FigureDefinition(
    definition:
        'A hey for three where one of the three is really a pair, one dancer close behind the other, weaving as a unit.',
    description:
        'The pair trades places each time it loops around an end: the front dancer swings wide and the one behind cuts inside to take the front. It is usually danced across the set, starting with the couple in the middle. The figure names who starts it and by which shoulder. A full dolphin hey usually takes 16 beats.',
  ),
  // TCB "Long wave", "Balance wave".
  'form_long_waves': FigureDefinition(
    definition:
        'Dancers along each side of the set join hands in a long wave, alternating facing into and out of the set.',
    description:
        'The figure names who faces in and can name who holds which hand. As a formation it takes no beats on its own; with a balance it usually takes 4.',
  ),
  // TCB "Long wave" (a single long wave in the center); renderer.dart
  // `form_a_long_wave` (in: the named dancers dance in; out: the other
  // dancers dance out of the center).
  // Note: no written reference describes the in/out options; the text
  // matches the app's model, inherited from ContraDB.
  'form_a_long_wave': FigureDefinition(
    definition:
        'Some dancers make a single long wave down the middle of the set while the others stay out of the center.',
    description:
        'Usually the role2s dance into the center and join hands in one long wave, often balancing it. The figure can also have the other dancers dance out of the center at the same time, or only dance out, leaving the named dancers in the middle. The full version usually takes 8 beats.',
  ),
  // TCB "Wave of four", "Circle to wave".
  'form_short_waves': FigureDefinition(
    definition:
        'Groups of four form short waves, lines of four with hands joined and each dancer facing the opposite way from the next.',
    description:
        'Typically the role2s hold left hands in the center while neighbors hold right hands at the ends. Waves usually run across the set, sometimes on a diagonal. The figure can include a balance, usually for 4 beats.',
  ),
  // TCB "Pass the ocean".
  'pass_the_ocean': FigureDefinition(
    definition:
        'Two couples facing across the set pass through and turn into a short wave of four.',
    description:
        'As they cross, the center dancers, usually the role2s, join left hands and turn a quarter, while the others step past and take right hands at the ends. It usually takes 4 beats, and a balance in the new wave often comes next.',
  ),
  // contra_taxonomy.dart alias `pull_by_dancers` -> pull_by {who: neighbors}.
  'pull_by_dancers': FigureDefinition(
    definition: 'A pull by with neighbors.',
    description:
        'Two neighbors take hands, usually right, and pull past each other, letting go as they pass. It takes 2 beats, or 4 with a balance first.',
  ),
  // contra_taxonomy.dart alias `pull_by_direction` -> pull_by {where: along}.
  'pull_by_direction': FigureDefinition(
    definition: 'A pull by along the set.',
    description:
        'Dancers facing each other take hands, usually right, and pull past each other along the set. It takes 2 beats, or 4 with a balance first.',
  ),
  // TCB "Seesaw".
  'see_saw': FigureDefinition(
    definition:
        'A dosido by the left shoulder: two dancers pass left shoulders, go back to back, and return.',
    description:
        'Dancers keep facing the same way as they go around. Once around usually takes 8 beats, most often with partners.',
  ),
  // TCB "Swat the flea"; Jennings "TWIRL TO SWAP".
  'swat_the_flea': FigureDefinition(
    definition:
        'A box the gnat with left hands: two dancers trade places, one turning under the raised arch.',
    description:
        'Usually the role2 turns under the joined left hands while the role1 walks around, and the pair ends facing each other in swapped places. It takes 4 beats, or 8 with a balance first.',
  ),
  // Maintainer definition (a swing introduced by a right shoulder round);
  // contra_taxonomy.dart alias `meltdown_swing` -> swing {prefix: meltdown},
  // paramBeats meltdown 16.
  'meltdown_swing': FigureDefinition(
    definition:
        'A swing that starts with a right shoulder round, the dancers circling face to face before taking hold.',
    description:
        'Dancers walk around each other by the right shoulder, keeping eye contact, and settle into an ordinary swing as they come around. Together the two parts usually fill 16 beats. It is most often danced with partners.',
  ),
};
