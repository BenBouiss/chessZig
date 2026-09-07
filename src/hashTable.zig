const std = @import("std");
const chess = @import("chess.zig");
const movel = @import("move.zig");
const boardl = @import("board.zig");
const configl = @import("config.zig");
const typel = @import("type.zig");
const weightl = @import("weights.zig");

const build_options = @import("build_options");

const e_piece = typel.e_piece;
const scoreType = typel.scoreType;
const depthT = typel.depthT;
const TT_strat = configl.TT_strat;

pub const Key: type = u64;
//pub const Key = struct {
//    code: u64 = 0,
//};

// note: the gain in space is not visible in the debug build
// will try to implement the chess programming version where way more stuff is stored

pub const zobristKeys: Zobrist_Keys = .{
    .pieceKeys = [12][64]Key{
        [64]Key{ 0xd0764d4f4476689f, 0x519e4174576f3791, 0xfbe07cfb0c24ed8c, 0xb37d9f600cd835b8, 0xcb231c3874846a73, 0x968d9f004e50de7d, 0x201718ff221a3556, 0x9ae94e070ed8cb46, 0x352cf3daf095ccc7, 0xeeefd63219b4a0d4, 0x8f3dfa98020e7942, 0xd99b8e00792f360d, 0xae14e77054359b98, 0x11ccbfbb36590dbd, 0x672fcfd4efd0e0bd, 0x8bc6e858d0501168, 0x367abb657f468b2e, 0xce254eaf1b0177e, 0x939e7abb81f5d5fc, 0x7784cb89e2481d7b, 0x296566311008aaa4, 0xdcda5b94829765e3, 0xa70de5b169e02435, 0x8686e981e604aa1c, 0xd0dafde236ba2593, 0x24896b7216d2d83c, 0x6d172ed3e81a7e8c, 0xf2eda4bfdf254cbb, 0x85ff42c6c6703f37, 0xdf321e3788bd2ceb, 0x15a0b07d583a481f, 0xa318445d13be8320, 0xb829333a229d7a38, 0x4775fb7db9c64a04, 0xfbf66cab58c5ce18, 0xb726234444b3460f, 0xc9eae0817bec39d6, 0x680386963ebb4053, 0x89eb358fd9821a96, 0xcca7e752da48d83d, 0xda7120595706973d, 0x2b5d999ce90ca71e, 0x77a22c4f769f4fdf, 0x977a0e80f0435870, 0xc3657ed88978d97, 0x6a22c726e186d3a2, 0xa4dee725ea8ec0a8, 0x94220f4a76070359, 0xc1ad5450730123f8, 0x3dfc82c5e51ecd63, 0xbe6d5f7cba543f17, 0x7d650780ce30aa72, 0x7405e883d0b9af7b, 0xcf43ed6994a6d3b3, 0xa062272dbbd8cd61, 0x2d058c37aeff1a86, 0xbccf20f4077763ad, 0x2ef7bb1d431319c6, 0xa6d8f28a297ebba4, 0xf77d1b5e9830d8b, 0xa78f9c5a19171faa, 0xf774ba509e10d54b, 0xd7f2b08901a4d152, 0xf648960c3bbe8add },
        [64]Key{ 0xf6a0ce4c583f417f, 0xa297dd606434a29f, 0x988361a80b1dcb8a, 0xceeb0c80be767c81, 0x425f0bac9515700d, 0x4c57527164dcc11, 0x11d6b04e4e40cf8d, 0xf7b39e975dc4802f, 0xdcb8101598dc6bea, 0x218320bff44d3ad4, 0x2baed980ffab1c97, 0x724b0098acbf19f6, 0x870bf81a415649e, 0x4b1df21950ad399a, 0xfcf98c59f2d83dec, 0x519dc75acd5f6acc, 0xa9bdb423b1db1f6d, 0x63e0fd440b132160, 0x29db76c385ae503c, 0x45ac5f6db1ed51b5, 0x6f85663a0be0c1b, 0x623c4e90f311b061, 0x4aa53d77d38a9fea, 0x597170bad78b55f7, 0x9d804d326833ba72, 0xa6001e257ed9a9f9, 0xe69228ca0fe7b3df, 0x1ee0085b6ddfe33e, 0xbf86652923dbc963, 0x99e2f3688ae73e9a, 0xd45c9b954c9c4361, 0x86d8c131f9d40b6b, 0x1d794276a8ce5c1f, 0xb65f174485fe74fa, 0x3fc1fcdc0aee5134, 0x2f8925758fab4030, 0xb2a33de25ca17dcd, 0x5d76a0dc556e1af2, 0x37cf8cf7a40b2ae, 0x3977cd3a3da1d1b7, 0xefeeeee3fd55600d, 0x3bc8d541cd041c38, 0xde91834a497eefd3, 0xfbe941191f8f6d3a, 0xbbd87b21466192a4, 0x6e2ac7c692c9e5c7, 0xb3d6a342267a4c49, 0xaa4001c3cb053694, 0xfffd3843a3f322f6, 0x9d3841bcf65e3e18, 0x44d10d765650096f, 0x485bca212b4aa1f0, 0x7c863aa23e0aab7c, 0xf728b6c163fe7982, 0xa35ebde627a5914d, 0x4cb3b81695bac578, 0x543bd02ec5d79dc9, 0x6b886dcae41c3f62, 0xabb75f60de5dc937, 0xd99b228814f27482, 0xe97a740307769e16, 0xf179b57df79936d2, 0xce7cb5bd8def31ad, 0x5065bc8bdb26e30d },
        [64]Key{ 0xef86849ce05fcca5, 0xa38a2f4f3b02ef24, 0x613deb54de0e392e, 0x6c1d598e8ac0fb23, 0xa11d8252fec380ad, 0xe9cc36011b4e27cc, 0x5d61d9a41f47cbad, 0x7605f30724df609e, 0x2eb3af2cf332e380, 0x71155c273ca15a19, 0xed006bf2a27d87c4, 0xa8e4e91083809f13, 0x9edcb3db0d95fd00, 0x3e85676d8b596ae9, 0x61f496fe6a9a2b71, 0x28748de3ff9210e3, 0x92356a874e42b18c, 0x34573a9cbc3da0bc, 0x7a4cce53f12bc00d, 0x6dcd6da65f8ef9f, 0x8b1763f330d395e0, 0xc2ca6fb8d16fe571, 0xa42fa8842aed9a24, 0xec712b14f4d696d5, 0x47bcbd693d544f03, 0x5c213b2046814b40, 0x4466b2c4a8e1bce3, 0x437774d82963bbe7, 0xa10abb8b3f641302, 0xc057c117f8f52e9, 0x857236cc09879dbd, 0xe25befddc06303, 0x9cd98b1c772f5660, 0x3fcb737a18021038, 0x3cf1b0559fca9ea7, 0x655f49711ea93c53, 0x66be4b2291ab42f6, 0x51ba62331b9bf54f, 0x8d3542ae91544598, 0xa6a1483bc6abc84c, 0xb74d390128a5c353, 0x320670d6498260ae, 0xd81e3a20ec59d29f, 0xf3dfb688ed84f336, 0x40c2f7299f8c9410, 0xec8a9e2905d749fc, 0xef2b8c995ce33932, 0x1b81859ce59789bd, 0xbabed4ae8718b668, 0xc2d6559acdd06cf6, 0x6a49f60cdfd76d04, 0x39f6e80d5d166d87, 0x24bc5a15a2af0c14, 0x79b40d8e2555cc26, 0xebf458254762d238, 0x6d292537fd8ce963, 0x1948d1d9577cdec1, 0x8167c2d0b9c32a4c, 0x9da466cc6bf7845, 0x6807412b139fc53b, 0x8a61d38e549d6565, 0x56a96d3dcfd0621e, 0xab7140cc2bee7efe, 0x82c05c801d80cd2b },
        [64]Key{ 0xe041397181770dbc, 0x69a54897e019486e, 0x2b630b3b3b5f942c, 0xe5e1bc50613973d0, 0x68e0bf2f4c03f745, 0x32b66548de05f02c, 0x3e352588f395891e, 0xb5d9edca7e4fe364, 0x3fe6e96710e49ef3, 0xfbb115d085896138, 0x92ac49e24011be89, 0x73f2b8d0ad131f32, 0xc550093d061890d8, 0xe54097956b32eeed, 0x65d6ced90e8add15, 0x34f62ada0bb582d7, 0xa9d3595b90ef9d18, 0xea70c6961d5e63ac, 0xd8b01d07b07586f2, 0xb8a000ad8f083161, 0xd1929625d10da10d, 0x1f4e3a543afc97d, 0xf2bd68be7687e885, 0xbde526977cebdda3, 0x1d996ecf4bd1e4e8, 0x8447201491b0fe1b, 0x70de159fcdbaa24d, 0xc29e4a4376f50387, 0x44aa9169104e9035, 0x2efed15f714e1d7b, 0xd6910295aae3a25a, 0x10ec9edc2074d924, 0x999c18ae23df6cd7, 0x5ebb0bc239f36057, 0xd5a30acc1f0e709e, 0x5e6610d08fbdfe8, 0x5ce6b84de4f2a561, 0xb3113428f334b14a, 0x8840946acc96da74, 0xae9ae3b8d572de71, 0xa82710b3a71fc883, 0x8a68eb10509164da, 0x7db7b2aa05f6f572, 0x1e285600f9a1ba67, 0x61208e103130fa92, 0xf92fd6d0f410b1a1, 0xa604c57c976f951f, 0xcaf62f1db0d73783, 0x417ec5add2d2ba4d, 0xb3c04b72c3930044, 0xbe1cf7a634efe95d, 0x267b6f8129ff8017, 0xafde6a5deaf074f5, 0xe90c44088ec7d9f6, 0xd3e69317e59a5c3, 0xc8b8f34bb8b1892a, 0xf83bbb7a3bc1a9cd, 0xf19d0d41b30ccfb2, 0xf4e86c546547fde6, 0xf0fd5372aa21d8e1, 0x39d7a5ec657a4344, 0x812f16377c602926, 0xb73ff8e70f37c3f9, 0xa48ec01540f77882 },
        [64]Key{ 0x4e36e9d44634c508, 0x543ba0f27cc3c6dd, 0x5fef5e0922919adf, 0x527c4ffa3ad01238, 0x74308e96737f93ba, 0x6b9139647add5ded, 0x52688921b86b4a8c, 0xa29d0fe00b43e1bb, 0x946f693408984d24, 0xf514e2c0cdfa3292, 0x6782302f146478d6, 0xbc6e1bc510d5830e, 0x4ab69016453a0665, 0xbb4a41c02c1e90f8, 0x5721c789672ce9e0, 0x107758cdb475f97b, 0x45bf99286e8fad86, 0xcaac99a2763ef2e7, 0x49a47ff4d12d78e8, 0xd76bd4ce067fccd7, 0x4894e5615fcee7bd, 0xad96dcd5ed89645a, 0x27b29605942c579, 0x16617a82fb69968f, 0xbe236116fa47bd2, 0xb5b6cb973c81c741, 0xab6465dfbb5fb053, 0x8eafa96952a69f7a, 0xadc9581cb9494899, 0xa01465a915a14d2b, 0xa2e459c331d90022, 0x1a06ed37394cf56f, 0xd71d1b2ccfe7581e, 0xdd28fe819004422c, 0x3c407c4409afca59, 0x67e321e1d5657216, 0x819a1c3c7cc81fd4, 0x6703fe6c82ee82c5, 0x4eaf3437469b191e, 0xd47722a53507b7d8, 0x51bf4a888ba661e3, 0xf20add85566c7518, 0xc17bb34ab974829e, 0x83cf3577e9b8db26, 0x9b819e7b90efccfc, 0xfc2e61143cb0d19, 0xf4a029ea9b933e30, 0x923d742158735628, 0x5392b0412e1d9d57, 0xa78a971ee18be004, 0x316a54bf83309960, 0xf3145f407b87e1d8, 0x9e635ded89e7cabd, 0xe90a39b26a84ac51, 0x329f33723a732e55, 0xbeae9ff9416fa443, 0x19f825250f09e677, 0xff3373398a204466, 0xe6c2560a2bd56af7, 0x483a78ed05d1c45e, 0x587e6bd3c2754611, 0x552ef1564ddeca90, 0xa13d3ac9b693b7f5, 0x9da972b7e6f369d4 },
        [64]Key{ 0xc5a64e46033519fb, 0xbf4051e7b67933af, 0xd65d890b2d13ed48, 0xe13b8594f5c55bdd, 0x45efb29b1b8153d2, 0xd3ec890c54f3fe0f, 0x802c80cd2a8be699, 0x56f408afb886af22, 0xd8b6b55d0791f0c, 0xd8ac473a2b213f0b, 0xe90b0cb986f747de, 0x2a4ad26f60fd37ca, 0x70cf6a342ca297fc, 0x91470eeeb793c3c, 0x474223bd7287792d, 0x12ac5caef55d4659, 0x6b6504277b731666, 0xb5ba5641a2e0fb2, 0xb0fb3f4b692da4cf, 0x4c2a4f1951d31b0f, 0xbea25e3d1bac85dd, 0x6fa7fc87cf7de5bb, 0xe5889bd943a9ed3f, 0xeb1f5731f5b96b4b, 0xe5ccbee714b60631, 0x938dcbcd6c539beb, 0x4b7c2c5c5cbdb9bf, 0x34296bfef22b858f, 0x93863776db9b8777, 0xb8153a0ed7d22118, 0xfe31d628a0d65825, 0x19142ff5c5707196, 0xb18c96f84efe51c4, 0xcd52c8bbb6f6dcfd, 0x96474537b4223ebf, 0xcfcf2c1f526e3a6d, 0xef79fc497cadd9a6, 0x646adaffd82980f3, 0xddbcdc769eaae62, 0x41636734fa0249eb, 0xec5b6bbf969984a4, 0xa667b997f03c4927, 0xcdc22085979512b6, 0x17908d90b838b5ee, 0x98d861f489d135, 0x7e547d723eb731e3, 0xe70a28f26d06db18, 0xf97a36649852b886, 0x25ccdd53413e5fbe, 0xad7777c8489750b0, 0x2c53ddb0851a1cfb, 0x199dc8d97e4fd912, 0xae7dd7d2f3a8cf49, 0x27c6568edc01d0c9, 0x2a425a68b3b6d5ed, 0xf81c661e4e77dfb5, 0xded99f8712972b69, 0xb3c54db89f9d0a87, 0x9e99c28ddb1746f0, 0x1a7ccdabcd8224a3, 0x2aea1227a53e6f13, 0x403736a359d8b33a, 0x6813445750a21e79, 0xdacd53aa607279b8 },
        [64]Key{ 0xb5904f89dc85542f, 0xa0dfac8061691d95, 0x204f70bf232e6d1b, 0x762bb31b8ceaa061, 0x26f66aaf787c7061, 0xbe8944ec71044267, 0x93bfdba297fa47c1, 0x8856054b2509af8c, 0x7ff4637df9fb199e, 0x56a30432f5c6c341, 0x6122722233308ff9, 0x87b24a3ce8c585e1, 0x182b173d16fea6d9, 0xef5230906effb0e6, 0xe965dabbbdd10b87, 0xf3d0325c18fe17be, 0x2a20ac1bcecd4074, 0x704883c68b7f9eec, 0x5fc0f72baf5f5877, 0x746200cf3e7f7517, 0xc713cc8ba6a4da23, 0x622e866f5ea4f771, 0xce2b60033669eac0, 0x41e0cc89d51391b1, 0x5015cbe839e96dd1, 0x81cc955801430193, 0xd4c99990cc1c62da, 0x236d5fcdbcfc9f9e, 0x2199bbf2e9f826c2, 0x8393d66239e80de9, 0x14b67c7b70eb8b6a, 0x305796be75380608, 0x4ddec014f506d112, 0x635cffd088c0ccbe, 0x59636ac9c36d190d, 0xa2172a775f2ab4e, 0x8cad1ee3c408a837, 0xbc279efeea8d6305, 0x8a797f751be8aab9, 0x945bd561ade0ef2c, 0xb8fc3fcdf74f30d6, 0xe4f57ad637f793b4, 0x9970f9d56734df67, 0xf8407bf9080954d9, 0xbb923f2b8fafdb35, 0xd08aaad437c5a27c, 0x83f6d5981c308c48, 0x1b86f6926dd2a4a4, 0xd8eea02548acf10, 0xcbf6ed17c47d4098, 0xf948827cb183fa72, 0x895565cea56886e9, 0xc16e0f5b0f0699c9, 0x6d065bf2fdef3fbc, 0x94d44089ba5db879, 0x62aa60fb51eeb9ec, 0x15eb80432d9acfeb, 0xa15f560e5447703f, 0x4efeccd5269cc95a, 0xec6409450cfc357d, 0x94bb44e34d4fa68a, 0x10feaa39b24fbb8f, 0x8fef84d2b94a50b, 0xf31198b1656ecd4b },
        [64]Key{ 0xbeeb68eda148938, 0x16acb72a3644ca94, 0xe874e71f1bf93656, 0x89a6a5af6e7da84, 0x1c8316c22972ecff, 0x89d9f38d408756bb, 0x7c83696fa0b1e270, 0x5c80133882f3a7b9, 0x3458e8d11f9af493, 0x74c08c1e43f2558a, 0x31bafb6ea12657bf, 0x43cacfe767a624fe, 0x5a3dbf3f5b56e1d9, 0x79e5431d2bc1c7df, 0x9dc795d2570dae4f, 0x29d6c5a63f844a92, 0xb01f5ee2c8bde5c7, 0x4dd3bf7f929579c2, 0x630b91b0ef311f02, 0x61e1f39a0dd7c6a2, 0x61bef01d3d28503b, 0xfac51cac65860917, 0xb4ca83fc732da75f, 0x31fcf5e13d4bc14, 0x76058a9bb615686c, 0x852eb8f42c43018a, 0x168a116a911f2e19, 0x121924560914b95, 0x63cfdb961f67d6be, 0xa26eb94ca0f8105f, 0xcfea24c57552a263, 0x7eaa118ee8f6556e, 0x6c8c0a277798d866, 0xfc09fe6a03ca935, 0xc208cc0619a01940, 0x2607adfa11336ae, 0xe4533afbd7fd7f31, 0x3f9665ad6200863d, 0xe365b9c4e4dffbe5, 0xa778ad2a25335ffb, 0x81f7c7f084f23bbb, 0x8c499c88fe76742d, 0xbe7513df7eb162d8, 0x1333fa12e3f6b62c, 0x33b7996e5beb8707, 0x505e129f4213d4b3, 0x8b2960068ab7f98f, 0x400739b03bbe4401, 0x62d90587096a8424, 0x752d9caf7f8bcd60, 0x2590544ef78ba5b0, 0xe016d869452e4af4, 0xef6434568bca1511, 0x21b9d73fd2469b3f, 0x159cea80d1735208, 0x38fb1e279fcba49c, 0x1246036c39a1db50, 0x768597d280aa1da0, 0xb501848fd5212198, 0x22e7d4a3c2c140a9, 0x574d49358f11356c, 0x9257bc38d3886840, 0xfc59cd721957d35d, 0x50df48008b77e827 },
        [64]Key{ 0x5f65a80f478303b0, 0x9e308f43b18d919d, 0x51de613eab0dd126, 0xe1f6342c562c1d66, 0x6ca39a4ebc9f98ac, 0x1008b23c2d9d3076, 0x861de2544b4569c8, 0xfa8866cf3694a435, 0xfb10d28c69363440, 0xce8ded79ad7243b3, 0xb956f1d0c1908875, 0xe81df5fa7bec6d46, 0x7134469494125894, 0x427ce0c38c6142f1, 0x7f505f4ddefec5b0, 0xb15b1027ad842f99, 0xf2baf00d6ddee338, 0xbe36863c2ef91732, 0x2aa1c57771489bf5, 0xc64e237e484864f5, 0x8aa67e1a668263fc, 0xd67e0b811f6a85c0, 0x96791f60b4570bff, 0x4417d766d7d32fa5, 0x81baf22e003a8712, 0xe1ef5e4d514385c4, 0xf7eae26e7165e8fa, 0x2af960fe6fc4407e, 0xda70aeaeac631e7c, 0x1ae99ab0273c6aff, 0xfb7c18c0aa9c0075, 0xd0a5f2da4924d16b, 0x1691a35813ee060b, 0xc4d90bc1bf20b4ee, 0x4cfa9038ada5fd11, 0x4536f7acc70a0612, 0x2fc8797273e8b259, 0x184f07fed3c6f0f2, 0x58e3eba9f3ac1d45, 0xb132e789b33a406e, 0x4369ddc34c30e150, 0xaf03a89f504a93ba, 0x1f66a8fcf2a4d1e, 0x8024ce67d0582307, 0x4bc1e731918f63b8, 0x407950799fbee618, 0xe81c7b93c5acb207, 0xb8c9ee29d5d7416c, 0x91334c801f0b1a5d, 0x52b43de64beb808d, 0xe54a50e5c9e4a397, 0x919f8b2e0dc534fe, 0xf5b25910755464bc, 0x3421e83057470591, 0xbbf6f681d28e0b8d, 0xc953fb9f7208c0cd, 0x5a3fc007cc8a9239, 0x1200d3804cbcc52b, 0x9351077a2281948f, 0xd8863a41c3fdae5b, 0xcd47502d7169c3fa, 0x940eac35a81c7cab, 0xc98b004e93cf2550, 0xc8f648c143c52065 },
        [64]Key{ 0xdbcaca9c02fec081, 0xede9ed726a28ec7f, 0xb37e09f90a24c596, 0xec09029d9172a91b, 0x1db33c535e873f3, 0x45b6b52a82ce7bcc, 0xdefcb441e1a5340c, 0x15ad35f8e6aa390c, 0x3f11519d94dc1e36, 0x39cbc91293e3b890, 0x464ceac7ef4b66ea, 0x579de98ca568d917, 0xb5611f873139e456, 0xaa466bdbc2ff7bde, 0xb154da60968d55bc, 0x8ac09a0d7c748a4b, 0x8e7954c2922d5938, 0x2babcf6a4dede3d9, 0x6bea121ae0470c2f, 0xfd9469a3d1beb88b, 0x22e11defdf6f462f, 0x34c60d9d1387aa1e, 0x759ecb4cebc0b981, 0x5ce1781db3a8d131, 0x43ca5b30905f2cb, 0x898bf9d0ae87394a, 0xb371f50a7dd77383, 0x468cdeef9a3dc5a4, 0xbc2e9dd6a2a7e538, 0xd5e3878b2ab10f53, 0x62ddcf5ad0eab0d3, 0x970efb2c746e5e63, 0xbfe786bcbea7d127, 0xba8111e1c71685f, 0x47e6e163e5effee8, 0x29befeccb13f6092, 0x945923d1218c4969, 0xbb2975e8cc620f45, 0xe4121b9f2190d57d, 0x886f851246642a34, 0xa66399da2648b0b3, 0xf45155939574d32f, 0x8b82c2d621330386, 0xc79ee593fd94593c, 0x3d91007145b856a9, 0x224399179e0e06dd, 0xc7d4eb1b2cab6b2d, 0xdec1ffd66372f28d, 0x893a10e87e10a59c, 0xd6b8a8d4b3bb5167, 0x13ce036d665e5538, 0xcb72bd67f4c37bb0, 0x630e45218c7a15e2, 0xcc2ec1f061a9b415, 0x52af07647757ffba, 0xad1e2eeda08a57f9, 0x57fad94fde7420fa, 0x6f60593f363b7b3c, 0xc4de523efd46a577, 0x50b229a81f34cf81, 0x9e3275e79f6193ed, 0x373604cad33e85e9, 0xd94b3b72b67a769, 0xeeed21bf9ac66c12 },
        [64]Key{ 0xce90352ff961f758, 0xee5eca2b1bc1a1f, 0xd81fa4a92c55873d, 0xc539484db7f1f55b, 0x9bfb8a1584036524, 0x39c33493e07f8a36, 0x7e525d4e041c09e0, 0xa28b0b98e361deb5, 0xef695051933b773a, 0x9fcb4b675f92668e, 0x6d2a59511ede19b5, 0x2189fe3e77b34aaf, 0x53c85b51c3db1bbc, 0xe3a6bc061051d0a5, 0xc93611d0400fdd0a, 0xeef17c0f3d648b0b, 0x41696cf0e9794793, 0x3af3975aa4540b42, 0xc918d97793b4ac02, 0x93701666973e7f3e, 0xb6a8bce63c9a48ec, 0x9f1163965dcb0dba, 0xe4cfc39321836e11, 0xf427645c7d5113d2, 0x43d17855f054425a, 0x4f09e1abbfbcfe3f, 0xe27abf13cadf1aaf, 0x8bcc12a8aec604d6, 0x1494a0c357c6b7e, 0x9bd50e8089a4b776, 0xae5ab91a410a1684, 0xa3d45604a22fab47, 0xf9d7028e8eec4783, 0x6aa189d22c409f08, 0xca3e08b048b3426b, 0x315222d7cd6a1909, 0x2f4835dd58aa3fe6, 0xddd6e66825bfaad1, 0xc4ec99c1b62d7e1e, 0x2c0519ab961a8f3, 0xd45b64f18938bdbb, 0x17f256ad34992b23, 0x5da5544ee84117b9, 0x4e718a3f9238ffac, 0xee02b85e4ec44187, 0xf6d5d2b30df7e35c, 0x7cdea865d3cd4d6d, 0x6c96bc20fb3c60d2, 0xd644412473017479, 0xd3482fe57290efeb, 0x9905588de2b8ff7a, 0xa203584ef2980f24, 0x845ccabf412cd9c7, 0x8bb43c4fd67bb840, 0x314cf1e72dbc92b8, 0x99d28f9502a1327e, 0x167c7ad556b3a878, 0x613e74ea2e50a7cc, 0xa13989ec9a68c5db, 0x5ae0c5bdc570d0ec, 0x6375c880c8472f69, 0xca0f7c9ed0f7b26c, 0x62d59fa4d8718c9b, 0x88486b8e527f9819 },
        [64]Key{ 0xffa6cd759aca178f, 0x57aabeb9ca1831d7, 0xd414437ee1ae9d1, 0x2f73521f97fa7399, 0xfa0b5876222d2587, 0xa0b4e5dff7bbf67f, 0xce1259cc15fcf244, 0xee49d279fb143bf, 0x4a6a5158cdbf5f62, 0x6f15f79cab1f6f7c, 0x35df3254a0ef51eb, 0x394ae0d70260480c, 0x7f44e101bf4a8fc3, 0xba5f41bb60a0ad5b, 0x8b52d9acdeed1380, 0xf4e5417aca664e77, 0x58c3729b4c6ae9e6, 0xdbdcb42cf367aeb3, 0x8d007ac4a7829c08, 0x7becb2af67a7bec4, 0x887ece4106f706ac, 0x9ce8949a70eb248c, 0x5c6c2ceb61c816b3, 0xa3427a5ba3f35dca, 0x26d668976ac648c8, 0x224df9993fd411d7, 0x2c07138f96f7fd72, 0x48ccbff98012fc39, 0x507741cfab7d1324, 0x76c6a144c2a6fb7, 0xfe90579c06823479, 0x2a17bceb9bd969de, 0xdff56f3d1e251a71, 0x4cf97fbe838448d4, 0x29d2622b32ab87b6, 0x2f0b00eb080e54ca, 0x57add25775c21c3f, 0xd6b16c32c9e0cb65, 0x297d8068f9c0c995, 0xfbaceb0f65644542, 0xe2ac71e98108abfb, 0x62b04e0d7edf7b47, 0xe7f2133eb393872f, 0x47c04f9d685a75b0, 0xdfa3d5546ded4945, 0xe17225818761b7b, 0x3b7c2d3012303d86, 0x90f0dc52d6f671bb, 0xeaef6eb31e79a1c8, 0x1500df03848f63e0, 0x67fa3af1389ab7f7, 0x257e83adc8cf0a37, 0x83cd866b40273c46, 0x610cdfbdb9606b4f, 0x7df83e7b07c85fc7, 0x2b59089574502bee, 0x62613ef74fe463a4, 0x94a32c5978578fce, 0x7995db7eda1b1396, 0x75ba1e8a102b4b2c, 0x35f901a23a0feec5, 0xa6a0ebad6f5a6dfe, 0x6f44fbe441a9deb1, 0x58a2f9283b1354c6 },
    },
    .turnKey = [2]Key{
        0x9e9ee2892db8d75,
        0x332d800a3725ea42,
    },
    .playKey = 0x3ac46e22a5fe6737,
    .castlingKeys = [16]Key{ 0xefbeddfce36329f, 0xf55233a7cf17b5e7, 0x742033122af1b745, 0x31a4ee69d5e8233e, 0x9f4c6f4f46949f06, 0xca5c21aaa50f0ce5, 0x7064df4db212f057, 0x40b4a32bb6994b70, 0xd6284cec5aee5a72, 0x5214403a97de5188, 0xc0aaad48f53d491b, 0x2bb58dd45d66c7f1, 0xbfe60591ab5efe51, 0xde6353979154e4a0, 0xe8812ee6e693d632, 0x741976696c7e21ff },
    .enPassantKey = 0xe8fad8b1b2942571,
};

pub const subKeyType = u16;
pub const KEY_SHIFT = 64 - @bitSizeOf(subKeyType);
pub inline fn keyToUpperKey(key: u64) subKeyType {
    return @intCast(key >> KEY_SHIFT);
}

pub inline fn qualityHeuristic(entry: Hash_entry, nNodes: scoreType) scoreType {
    const diff = @mod(MAX_AGE + nNodes - @as(scoreType, @intCast(entry.age())), MAX_AGE);
    return entry._depth - diff * 8;
}

// Types of nodes:
//  ALL: Upper bound: less than alpha
//  UPPER: or Exact Complete evaluation of a position done a depth 0 to be compared with alpha
//  LOWER: Lower bound: greater or equal than beta. Induced a beta cutoff to be compared with beta
//
pub const nodeType = enum(u2) { INVALID, UPPER, ALL, LOWER };

const NODETYPE_mask = 0x3; //000000xx
const AGE_MASK = 252;
const AGE_SHIFT = 2;

const MAX_AGE: u8 = 64;
const MAX_AGE_AND: u8 = 63;

pub const Hash_entry = struct {
    // 16 + 16 + 16 + 8 + 8 + 8
    // = 72bit = 9 bytes
    key: subKeyType align(1) = 0,
    staticEval: i16 align(1) = 0,
    searchScore: i16 align(1) = 0,

    bestMove: movel.IMove align(1) = .{},
    _depth: u8 = 0,
    // age + bound
    val: u8 = 0,
    pub fn init(key: subKeyType, bestMove: movel.IMove, depth: u8, a: u8, node: nodeType, eval: i16, s: i16) Hash_entry {
        const val: u8 = @as(u8, @intFromEnum(node)) | (a << AGE_SHIFT);
        return .{ .key = key, .bestMove = bestMove, ._depth = depth, .val = val, .staticEval = eval, .searchScore = s };
    }
    pub inline fn valid(self: Hash_entry) bool {
        return self.nodeT() != .INVALID;
    }
    pub inline fn nodeT(self: Hash_entry) nodeType {
        return @enumFromInt(self.val & NODETYPE_mask);
    }
    pub inline fn age(self: Hash_entry) u8 {
        return self.val >> AGE_SHIFT;
    }
};
pub fn ttEvalToEval(hashEval: scoreType, ply: depthT) scoreType {
    if (hashEval == typel.scoreNone) {
        return typel.scoreNone;
    }
    if (chess.isMateWin(hashEval)) {
        return hashEval - ply;
    }
    if (chess.isMateLose(hashEval)) {
        return hashEval + ply;
    }
    return hashEval;
}
pub fn evalToTTEval(score: scoreType, depth: depthT) scoreType {
    if (score == typel.scoreNone) {
        return typel.scoreNone;
    }
    if (chess.isMateWin(score)) {
        return score + depth;
    }
    if (chess.isMateLose(score)) {
        return score - depth;
    }
    return score;
}

pub inline fn buildEntryFromMatchResult(key: Key, depth: u8, eval: scoreType, score: scoreType) Hash_entry {
    // only used in testing
    return .init(keyToUpperKey(key), .{}, depth, hashTable.gen, .ALL, @intCast(eval), @intCast(score));
}

pub inline fn buildEntryMatchExt(key: Key, depth: u8, nodeT: nodeType, bestMove: movel.IMove, eval: scoreType, score: scoreType) Hash_entry {
    return .init(keyToUpperKey(key), bestMove, depth, hashTable.gen, nodeT, @intCast(eval), @intCast(score));
}

pub const getResult = struct {
    nextIdx: u8 = 0,
    entry: ?Hash_entry = null,
    nextPerfectHit: bool = false,
};
pub const probeResult = struct {
    writer: hashWriter = .{},
    entry: ?Hash_entry = null,
};
pub const hashWriter = struct {
    bucket: *Hash_bucket = undefined,
    idx: u8 = 0,
    nextPerfectHit: bool = false,

    pub inline fn init(key: u64) hashWriter {
        return .{ .bucket = hashTable.getBucketFromFullHashIndex(key) };
    }
    pub inline fn writeShort(self: *hashWriter, entry: Hash_entry) void {
        const prev = self.bucket.entries[self.idx];
        if (self.nextPerfectHit) {
            if (prev._depth > entry._depth) {
                hashTable.stat.missInsertion += 1;
                return;
            }
            //if ((prev._depth == entry._depth) and (prev.nodeT() == .ALL)) {
            //    hashTable.stat.missInsertion += 1;
            //    return;
            //}
        }
        self.bucket.entries[self.idx] = entry;
        hashTable.stat.insertion += 1;
    }

    pub inline fn write(self: *hashWriter, entry: Hash_entry) void {
        const stat = self.bucket.addEntry(entry, configl.DEFAULT_TT_STRAT);
        if (stat) {
            hashTable.stat.insertion += 1;
        }
    }
};

pub const Hash_bucket = struct {
    entries: [configl.ITEM_PER_BUCKET]Hash_entry align(32) = @splat(.{}),

    pub fn printSize(p_self: *const Hash_bucket) void {
        std.debug.print("[DEBUG] printSize: hash bucket = {d} bytes\n", .{@sizeOf(Hash_bucket)});
        std.debug.print("[DEBUG] printSize: entries size is {d} bytes\n", .{@sizeOf(Hash_entry)});

        _ = p_self;
    }

    pub fn len(self: Hash_bucket) u8 {
        var ret: u8 = 0;
        for (0..configl.ITEM_PER_BUCKET) |i| {
            ret += @intFromBool(self.entries[i].valid());
        }
        return ret;
    }
    pub fn addEntry(p_self: *Hash_bucket, entry: Hash_entry, comptime strategy: TT_strat) bool {
        switch (strategy) {
            .ALWAYS_REPLACE => {
                return p_self.addEntry_AR(entry);
            },
            .KEEP_DEEPER => {
                return p_self.addEntry_deep(entry);
            },
        }
    }

    pub fn addEntry_deep(p_self: *Hash_bucket, n_entry: Hash_entry) bool {
        var idxS: usize = 0;
        var sDepth: u8 = 255;
        const reqDepth = n_entry._depth;
        // if a better entry exists for this hash key we exit
        const a = n_entry.age();
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            const currDepth = entry._depth;
            if (!entry.valid() or (entry.age() + configl.OLD_THRESHOLD) < a) {
                p_self.entries[i] = n_entry;
                return true;
            }
            if (entry.key == n_entry.key) {
                if (currDepth > reqDepth) {
                    return false;
                }
                p_self.entries[i] = n_entry;
                return true;
            }

            if (currDepth < sDepth) {
                idxS = i;
                sDepth = currDepth;
            }
        }

        p_self.entries[idxS] = n_entry;
        return true;
    }

    pub fn addEntry_AR(p_self: *Hash_bucket, entry: Hash_entry) bool {
        _ = p_self;
        _ = entry;
        //p_self.entries[p_self.len] = entry;
        //p_self.len = (p_self.len + 1) % configl.ITEM_PER_BUCKET;
        return true;
    }

    pub fn getEntryMatchNext(p_self: *Hash_bucket, hash: u64, depth: u8, p_state: *const boardl.boardState, nNodes: scoreType) getResult {
        _ = depth;
        const _hash = keyToUpperKey(hash);
        var next: usize = 0;
        var worstQuality: scoreType = 0;
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            // note: now that only one instance of the key gets stored, the highest depth is the first one to get hit
            if (entry.key == _hash and p_state.isMovePseudoLegal(entry.bestMove)) {
                return .{ .entry = entry, .nextIdx = @intCast(i), .nextPerfectHit = true };
                //if (entry._depth >= depth) {
                //    hashTable.stat.hit += 1;
                //    return .{ .entry = entry, .nextIdx = @intCast(i), .nextPerfectHit = true };
                //} else {
                //    hashTable.stat.miss += 1;
                //    return .{ .entry = null, .nextIdx = @intCast(i), .nextPerfectHit = true };
                //}
            }
            if (!entry.valid()) {
                hashTable.stat.miss += 1;
                return .{ .entry = null, .nextIdx = @intCast(i), .nextPerfectHit = false };
            }
            const quality = qualityHeuristic(entry, nNodes);
            if (i == 0 or quality < worstQuality) {
                worstQuality = quality;
                next = i;
            }
        }
        hashTable.stat.miss += 1;
        return .{ .entry = null, .nextIdx = @intCast(next), .nextPerfectHit = false };
    }
    pub fn getEntryMatch(p_self: *Hash_bucket, hash: u64, depth: u8) ?Hash_entry {
        const _hash = keyToUpperKey(hash);
        for (0..configl.ITEM_PER_BUCKET) |i| {
            const entry = p_self.entries[i];
            if (entry.key == _hash and entry._depth >= depth) {
                hashTable.stat.hit += 1;
                return entry;
            }
        }
        hashTable.stat.miss += 1;
        return null;
    }
};

pub const hashTableStat = struct {
    hit: u64 = 0,
    miss: u64 = 0,
    insertion: u64 = 0,
    missInsertion: u64 = 0,
};
pub const Hash_table = struct {
    entries: []Hash_bucket,
    MBsize: u32 = 0,
    closestBit: u8 = 0,
    size: u64 = 0,
    initialized: bool = false,
    stat: hashTableStat = .{},
    mask: u64 = 0,
    gen: u8 = 0,

    pub fn init(alloc: std.mem.Allocator, MBsize: u32, verbose: bool) !Hash_table {
        var ret: Hash_table = undefined;
        ret.MBsize = MBsize;

        var total_size: u64 = @intCast(MBsize * 1024 * 1024);
        total_size = @divFloor(total_size, @sizeOf(Hash_entry) * configl.ITEM_PER_BUCKET);

        ret.closestBit = chess.l_getMsbIdx(total_size) - 1;
        ret.size = chess.xToBitboard(ret.closestBit);
        ret.mask = ret.size - 1;
        ret.entries = (try alloc.alloc(Hash_bucket, ret.size));

        ret.zero();
        ret.initialized = true;

        if (verbose) {
            std.debug.print("[PRE] Initializing hash table with a size of {d} buckets closest bit {d} for input of {d}MB = {d} msb total size {d}! Total allocated size {d} bytes for {d} entries\n", .{ ret.size, ret.closestBit, MBsize, chess.l_getMsbIdx(total_size), total_size, ret.size * configl.ITEM_PER_BUCKET * @sizeOf(Hash_entry), ret.size * configl.ITEM_PER_BUCKET });
            ret.getBucket(0).printSize();
        }
        return ret;
    }
    pub inline fn getBucket(p_self: *Hash_table, bucketIdx: u64) *Hash_bucket {
        return &p_self.entries[bucketIdx];
    }
    pub fn zero(p_self: *Hash_table) void {
        for (0..p_self.entries.len) |i| {
            p_self.entries[i] = .{};
        }
        p_self.stat = .{};
        p_self.gen = 0;
    }
    pub fn free(p_self: *Hash_table, alloc: std.mem.Allocator, verbose: bool) void {
        if (verbose) {
            std.debug.print("[FREE] Freeing the entries in the hashtable \n", .{});
        }
        if (p_self.initialized) {
            alloc.free(p_self.entries);
            p_self.initialized = false;
        }
    }

    pub inline fn nextGeneration(self: *Hash_table) void {
        // to be used at each node root
        self.gen = (self.gen + 1) & MAX_AGE_AND;
    }

    pub inline fn getHashIndex(self: Hash_table, hash: u64) u64 {
        return hash & self.mask;
    }
    //pub inline fn getHashIndex(self: *const Hash_table, hash: u64) u64 {
    //    return @intCast((@as(u128, @intCast(hash)) * @as(u128, @intCast(self.size))) >> 64);
    //}

    pub inline fn getBucketFromFullHashIndex(self: *Hash_table, hash: u64) *Hash_bucket {
        const index = self.getHashIndex(hash);
        return self.getBucket(index);
    }

    pub fn overwriteEvaluationEntries(p_self: *Hash_table, p_entry: *Hash_entry, eval: scoreType) void {
        const index = p_entry.key;
        var p_bucket = p_self.getBucketFromFullHashIndex(index);
        for (0..configl.ITEM_PER_BUCKET) |i| {
            var ent = &p_bucket.entries[i];
            if (ent.key == p_entry.key) {
                ent.staticEval = eval;
            }
        }
    }
    pub fn storeEntry_cst(p_self: *Hash_table, p_entry: Hash_entry, key: u64, comptime strategy: TT_strat) bool {
        var p_bucket = p_self.getBucketFromFullHashIndex(key);
        const stat = p_bucket.addEntry(p_entry, strategy);
        if (stat) {
            p_self.stat.insertion += 1;
        }
        return true;
    }

    pub fn probeMatch(p_self: *Hash_table, key: u64, depth: u8, p_state: *const boardl.boardState, nNodes: scoreType) probeResult {
        const p_bucket = p_self.getBucketFromFullHashIndex(key);
        const res = p_bucket.getEntryMatchNext(key, depth, p_state, nNodes);
        return .{ .writer = .{ .bucket = p_bucket, .idx = res.nextIdx, .nextPerfectHit = res.nextPerfectHit }, .entry = res.entry };
    }
    pub fn storeEntry(p_self: *Hash_table, entry: Hash_entry, key: u64) bool {
        var p_bucket = p_self.getBucketFromFullHashIndex(key);
        const stat = p_bucket.addEntry(entry, configl.DEFAULT_TT_STRAT);
        if (stat) {
            p_self.stat.insertion += 1;
        }
        return true;
    }
    pub fn countNonEmpty(p_self: *Hash_table) u64 {
        var ret: u64 = 0;
        for (0..p_self.size) |i| {
            ret += @intFromBool(p_self.getBucket(i).len() != 0);
        }
        return ret;
    }
    pub fn countValids(p_self: *Hash_table) u64 {
        var ret: u64 = 0;
        for (p_self.entries) |e| {
            ret += @intCast(e.len());
        }
        return ret;
    }

    pub fn getMostUtilized(p_self: *Hash_table) u8 {
        var ret: u8 = 0;
        for (0..p_self.size) |i| {
            const e = p_self.getBucket(@intCast(i));
            ret = @max(ret, e.len());
            if (ret == configl.ITEM_PER_BUCKET) {
                break;
            }
        }
        return ret;
    }
    pub inline fn prefetchHash(self: *Hash_table, hash: u64) void {
        const index = self.getHashIndex(hash);
        @prefetch(&self.entries[index], .{ .cache = .data, .locality = 0, .rw = .read });
    }
};

pub inline fn getEntryFromMatch(key: Key, depth: u8) ?Hash_entry {
    var p_bucket: *Hash_bucket = hashTable.getBucketFromFullHashIndex(key);
    return p_bucket.getEntryMatch(key, depth);
}

pub const Zobrist_Keys = struct {
    pieceKeys: [12][64]Key = std.mem.zeroes([12][64]Key),
    turnKey: [chess.NUMBER_PLAYER]Key = std.mem.zeroes([chess.NUMBER_PLAYER]Key),
    playKey: Key = 0,
    castlingKeys: [16]Key = std.mem.zeroes([16]Key),
    enPassantKeysNine: [9]Key = std.mem.zeroes([9]Key),

    enPassantKey: Key = 0,
    pub fn init(seed: u64) Zobrist_Keys {
        var ret: Zobrist_Keys = .{};
        var rngIntGenerator = std.Random.DefaultPrng.init(seed);
        const rng = rngIntGenerator.random();
        initZobristKeys(rng, &ret);
        return ret;
    }
    pub fn print(self: Zobrist_Keys) void {
        std.debug.print("pieceKeys: {{\n", .{});
        for (0..12) |p| {
            std.debug.print("{{", .{});
            for (0..64) |sq| {
                std.debug.print("0x{x},", .{self.pieceKeys[p][sq]});
            }
            std.debug.print("}},\n", .{});
        }
        std.debug.print("}}\n", .{});

        std.debug.print("turnKey: \n", .{});
        std.debug.print("{{", .{});
        for (0..2) |p| {
            std.debug.print("0x{x},", .{self.turnKey[p]});
        }
        std.debug.print("}}\n", .{});

        std.debug.print("playKey: 0x{x}\n", .{self.playKey});

        std.debug.print("castlingKeys: \n", .{});
        std.debug.print("{{", .{});
        for (0..16) |i| {
            std.debug.print("0x{x},", .{self.castlingKeys[i]});
        }
        std.debug.print("}}\n", .{});

        std.debug.print("enPassantKey: 0x{x}\n", .{self.enPassantKey});
    }
};

pub var hashTable: Hash_table = .{ .entries = undefined };

pub fn isHashTable_init() bool {
    return hashTable.initialized;
}
pub fn _initOrReallocHashTable(alloc: std.mem.Allocator, sizeHashTable: u32, verbose: bool) void {
    // size in MB

    if (verbose) {
        std.debug.print("[DEBUG] _initOrReallocHashTable: Building using hash logic!\n", .{});
    }
    if (hashTable.initialized) {
        if (sizeHashTable == hashTable.MBsize) {
            hashTable.zero();
            return;
        }
        hashTable.free(alloc, verbose);
    }
    hashTable = Hash_table.init(alloc, sizeHashTable, verbose) catch |err| {
        std.debug.print("[ERROR] _initOrReallocHashTable: memory error during alloc {}\n", .{err});
        @panic("Mem error");
    };
}

pub fn _freeHash(alloc: std.mem.Allocator, verbose: bool) void {
    hashTable.free(alloc, verbose);
}

pub fn initZobristKeys(rng: std.Random, zob: *Zobrist_Keys) void {
    //@setEvalBranchQuota(100000);
    for (0..12) |i| {
        for (0..64) |j| {
            zob.pieceKeys[i][j] = rng.uintAtMost(u64, chess.UNIVERSE);
        }
    }

    zob.turnKey[0] = rng.uintAtMost(u64, chess.UNIVERSE);
    zob.turnKey[1] = rng.uintAtMost(u64, chess.UNIVERSE);

    for (0..16) |j| {
        zob.castlingKeys[j] = rng.uintAtMost(u64, chess.UNIVERSE);
    }

    zob.enPassantKey = rng.uintAtMost(u64, chess.UNIVERSE);
    zob.playKey = zob.turnKey[0];
    zob.playKey ^= zob.turnKey[1];
}
pub const keySet = struct {
    key: Key = 0,
    pawnKey: Key = 0,
    nonPawnKey: [2]Key = @splat(0),
};
pub fn fullComputeZobristKeys(p_board: *const boardl.boardState) keySet {
    // for better perfs look for incremental xor key update using the previous move
    var ret: keySet = .{};
    ret.key = zobristKeys.turnKey[chess.whiteBoolToInt(p_board.whiteToMove())];

    for (0..chess.N_SQUARES) |i| {
        const piece = p_board.getPiece(@intCast(i));
        const color = chess.e_colorFromPiece(piece);
        if (piece != .nEmptySquare) {
            ret.key ^= zobristKeys.pieceKeys[@intFromEnum(piece)][i];

            ret.nonPawnKey[@intFromEnum(color)] ^= zobristKeys.pieceKeys[@intFromEnum(piece)][i];
        }
        if (chess.isPawnPiece(piece)) {
            ret.pawnKey ^= zobristKeys.pieceKeys[@intFromEnum(piece)][i];
        }
    }
    ret.key ^= zobristKeys.castlingKeys[p_board.frame.stat.castlingKey()];
    if (p_board.frame.enPassantIdx != 0) {
        ret.key ^= zobristKeys.enPassantKey;
    }
    return ret;
}

pub fn printTTStats() void {
    const n = hashTable.countNonEmpty();
    const frac: f64 = @as(f64, @floatFromInt(n)) / @as(f64, @floatFromInt(hashTable.size)) * 100;
    std.log.info("TT: {d:.2}% of buckets used, non empty {d} total {} buckets", .{ frac, n, hashTable.size });

    const nvalid = hashTable.countValids();
    const frac2: f64 = @as(f64, @floatFromInt(nvalid)) / @as(f64, @floatFromInt(hashTable.entries.len * configl.ITEM_PER_BUCKET)) * 100;
    std.log.info("TT: total utilization {d:.2}%", .{frac2});

    const util = hashTable.getMostUtilized();
    std.log.info("TT: most entries in a bucket {d}", .{util});

    std.log.info("TT: insertions {d} hit {d} miss {d} miss insertion {d}", .{ hashTable.stat.insertion, hashTable.stat.hit, hashTable.stat.miss, hashTable.stat.missInsertion });
    std.log.info("TT: gen {d}", .{hashTable.gen});
}
