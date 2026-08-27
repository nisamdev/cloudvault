/**
 * Words for passphrases.
 *
 * Short, common, unambiguous English — nothing that has to be spelled out over
 * the phone, no near-homophones, no plurals sitting next to their singulars.
 * A passphrase is the one password a person actually types from memory, so the
 * words matter more than the count.
 *
 * The list's size is what sets the strength, and the generator reports it
 * honestly rather than rounding up: 512 words is a little over 9 bits each, so
 * five words is about 46 bits and six is about 55.
 */
export const WORDS = `
able acid acorn actor adapt add adopt adult afford agent agree ahead aim air
alarm album alert alien alley almond alone alpha alter amber amble amend among
ample anchor angel anger angle ankle answer ant anvil apart apple april apron
arch arctic argue arise arm armor army aroma arrow art ash aside ask aspen
asset atlas atom attic auburn audio august aunt author auto autumn avenue avoid
awake award aware away axis bacon badge bagel baker balance balcony bald ballet
bamboo banana band banjo bank barge barley barn basic basil basin basket bat
batch bath baton beach beacon bead beam bean bear beast beaver bed beech beetle
began begin behind bell belong belt bench bend berry beside best beta better
beyond bicycle bike bind birch bird birth bishop bison bit bitter black blade
blame blank blast blaze blend bless blind blink block bloom blossom blue blur
board boat bold bolt bond bone bonus book boost boot border born borrow bother
bottle bottom bounce bound bow bowl box brain brake branch brass brave bread
break breeze brick bridge brief bright bring brisk broad bronze brook broom
brown brush bubble bucket buckle bud buffet build bulb bulk bull bundle bunker
burden burn burst bus bush butter button buy cabin cable cactus cage cake calm
camel camp canal candle cane canoe canvas canyon cape captain car carbon card
cargo carpet carrot carry carve case cash castle cat catch cattle cause cave
cedar celery cell cement census cereal chain chair chalk chamber chance change
chapel charm chart chase cheap check cheek cheer cheese cherry chess chest
chief child chill chimney chin chip chorus chosen cider cinema circle citizen
city civic claim clamp clarify class clay clean clear clerk clever cliff climb
clinic clock close cloth cloud clover club clue cluster coach coal coast coat
cobalt cocoa coffee coin cold collar colony color column comb combine come
comfort comic common compass concert concrete cone connect consider cook cool
copper copy coral cord core cork corn corner correct cost cotton couch cough
count county couple course cousin cover cow coyote cozy crab craft crane crash
crate crawl crazy cream create credit creek crew cricket crimson crisp critic
crop cross crowd crown cruise crumb crush crust cube cuckoo cup curb cure curl
current curve cushion custom cycle daily dairy daisy damp dance danger dark
dash data date dawn day deal dear debate decade decide deck decor deep deer
defend define degree delay delta demand dense dentry depart depend depth desert
design desk detail detect device diagram dial diamond diary diesel diet differ
dig digital dinner direct dirt disc discuss dish dismiss distant ditch dive
divide dizzy dock doctor dodge dog dollar dolphin domain donate donkey door
dose double dough dove down dozen draft dragon drain drama draw dream dress
drift drill drink drive drop drum dry duck dune dusk dust duty dwarf eager
eagle early earn earth easel east easy echo edge edit effort egg eight either
elbow elder elect elegant element elephant eleven elm else email embark ember
emerge empire employ empty enable enact end enemy energy engage engine enjoy
enough enrich enter entire equal equip era errand escape essay estate ethic
even event ever evolve exact exam example exceed excite exile exist exit expand
expect expert explain export extend extra eye fabric face fact fade faint fair
faith fall false fame family famous fan fancy far farm fashion fast fault favor
feast feather feature fee feed feel fellow fence fern ferry festival fetch
fever few fiber fiction field fifteen fifty fig figure file fill film filter
final find fine finger finish fire firm first fish fist fit five fix flag flame
flash flat flavor flax fleet flesh flight flint float flock flood floor flour
flow flower fluid flute fly foam focus fog foil fold folk follow food foot
force forest forget fork form fort forty forum forward fossil foster found four
fox fragile frame free freeze fresh friend fringe frog front frost fruit fuel
full fun funnel fur future gadget gain galaxy gallery game garage garden garlic
gas gate gather gauge gaze gear gem gene gentle genuine ghost giant gift ginger
give glad glance glass glide globe gloom glory glove glow glue goat gold golf
good goose govern gown grab grace grade grain grand grape graph grasp grass
gravel gray great green greet grid grill grin grip grocery groove ground group
grove grow guard guess guest guide guitar gulf gum gym habit hair half hall
hammer hamster hand handle happy harbor hard hare harvest hat hatch have hawk
hazel head heal health heap heart heat heavy hedge heel height helmet help hen
herb herd here hero hidden high hill hint hire hobby hockey hold hole holiday
hollow home honest honey hood hoof hook hope horizon horn horse hospital host
hotel hour house hover human humble humor hundred hunt hurdle hurry hurt hut
ice icon idea ideal idle ignore ill image impact import impose inch include
income indeed index indoor infant inform inherit initial injury ink inner input
insect inside insist inspire install intact intend into invest invite iron
island issue item ivory jacket jaguar jar jazz jeans jelly jewel job join joke
journey joy judge juice july jump june jungle junior just kayak keen keep
kernel kettle key kick kid kind king kiss kit kitchen kite kitten knee knife
knit knock knot know lab label labor lace ladder lady lake lamp land lane
language lantern lap large laser last late laugh launch laundry lava law lawn
layer lazy lead leaf lean learn lease leash least leather leave lecture left
leg legal legend lemon lend length lens leopard lesson letter level liberty
library license lid life lift light like lilac limb lime limit line linen link
lion liquid list listen little live lizard load loaf loan lobby local lock log
logic lonely long look loop lord lose lot loud love low loyal luck lumber lunar
lunch lung luxury lyric machine mad magic magnet maid mail main major make
mammal man manage mango manor mantle manual map marble march margin marine
market marsh mask mason mass master match matter mature maze meadow meal mean
measure meat medal media medium meet melody melon melt member memory mend menu
mercy merge merit merry mesh message metal method middle midnight mild mile
milk mill mind mine mineral minor mint minute mirror miss mist mix model modern
modest moment monkey month moon moral more morning mosaic most motion motor
mount mouse mouth move movie much mud muffin mule multiply muscle museum
mushroom music must mutual myself mystery nail name napkin narrow nation native
nature near neat neck need needle neighbor nephew nerve nest net network never
new news next nice night nine noble noise noon normal north nose note notice
novel now number nurse nut oak oasis oat object oblige observe obtain occur
ocean october odd offer office often oil okay old olive omit once onion online
only open opera opinion oppose option orange orbit orchard order organ origin
orphan other otter ounce outer output outside oval oven over owl own oxygen
oyster pace pack page paint pair palace pale palm panda panel panic paper
parade parcel parent park parrot part party pass past pasta patch path patient
patrol pattern pause pave paw pay peace peach peak pear pearl pedal peer pen
pencil people pepper perfect perform perhaps period permit person pet phase
phone photo phrase piano pick picnic picture piece pig pigeon pile pilot pin
pine pink pioneer pipe pitch pizza place plain plan plant plastic plate play
please pledge plenty plot plug plum plunge pocket poem poet point polar pole
police policy polish pond pony pool poppy porch port portion post pot potato
pottery pouch pound pour powder power praise prawn pray prefer prepare present
press pretty prevent price pride primary print prior prism prize problem
process produce profit program project promise proof proper protect proud prove
public pudding pull pulse pump punch pupil puppy pure purple purpose purse push
put puzzle pyramid quality quantum quarter queen quest question quick quiet
quilt quit quiz quote rabbit raccoon race rack radar radio raft rail rain raise
rally ranch random range rank rapid rare rate rather raven raw ray reach read
ready real reason rebel recall recipe record recover red reduce reef refer
reflect reform refuse region regret regular reject relax release relief rely
remain remember remind remove render renew rent repair repeat reply report
rescue resist resort resource respect respond rest result retire return reveal
review reward rhythm ribbon rice rich ride ridge rifle right rigid ring rinse
riot ripe rise risk ritual river road roast robin robot rock rocket rod role
roll roof room root rope rose rotate rough round route royal rubber ruby rug
rule rumor run runway rural rush rust sad safe sail salad salmon salon salt
same sample sand satisfy sauce save saw say scale scan scarf scatter scene
scheme school science scissor scope score scout scrap screen script sculpt sea
seal search season seat second secret section secure seed seek seem segment
select sell send senior sense sentence series serve session settle seven shade
shadow shaft shall shape share sharp shed sheep sheet shelf shell shelter
sheriff shield shift shine ship shirt shock shoe shoot shop shore short shoulder
shout show shrimp shrink shuffle sibling side siege sight sign silent silk
silly silver similar simple since sing single sink sir sister sit six size
skate sketch ski skill skin skirt skull sky slab slam sleep sleeve slender
slice slide slight slim slogan slope slot slow small smart smile smoke smooth
snack snake snap sneeze snow soap soccer social sock soda soft soil solar sold
soldier solid solve some song soon sorry sort soul sound soup source south
space spare spark speak special speed spell spend sphere spice spider spike
spin spirit split spoil sponge spoon sport spot spray spread spring spy square
squeeze stable stack staff stage stair stamp stand star start state stay steady
steak steam steel stem step stereo stick still sting stock stomach stone stool
stop store storm story stove strange straw stream street stress strike string
strong studio study stuff style subject submit subway such sudden suffer sugar
suggest suit summer sun super supply support suppose sure surface surge
surprise survey suspect swallow swamp swan swap swarm sweat sweet swift swim
swing switch sword symbol syrup system table tackle tag tail tailor take tale
talent talk tall tank tape target task taste tattoo taxi tea teach team tear
tell temple ten tenant tennis tent term test text thank that theme then theory
there they thick thin thing think third thirty this thorn those thread three
thrive throat throw thumb thunder ticket tide tidy tiger tight tile timber time
tiny tip tired tissue title toast today toe together toilet token tomato
tomorrow tone tongue tonight tool tooth top topic torch total touch tough tour
toward towel tower town toy track trade traffic trail train transfer trap
travel tray treat tree trend trial tribe trick trip trophy trouble truck true
trumpet trust truth try tube tuition tumble tuna tunnel turkey turn turtle
twelve twenty twice twin twist two type ugly umbrella uncle under unfair
uniform union unique unit unlock until upon upper upset urban urge usage use
usual valid valley value valve van vanish vapor variety vast vault vegetable
vehicle velvet vendor venture venue verb verify version very vessel veteran
video view village vintage violin virtual virus visa visit visual vital vivid
vocal voice void volcano volume vote voyage wage wagon waist wait wake walk
wall walnut want warm warn wash wasp waste watch water wave wax way weak wealth
weapon wear weather weave wedding weekend weight weird welcome well west wet
whale wheat wheel when where which while whip whisper white whole why wide
width wife wild will win wind window wine wing wink winner winter wire wisdom
wise wish witness wolf woman wonder wood wool word work world worry worth wrap
wrist write wrong yard year yellow yes yield yoga yogurt young youth zebra zero
zone zoo
`
  .trim()
  .split(/\s+/);
