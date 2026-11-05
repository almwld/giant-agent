class PlannerService {
  PlannerService._();
  static final PlannerService _instance = PlannerService._();
  factory PlannerService() => _instance;

  bool requiresPlan(String request) {
    final text = request.trim().toLowerCase();
    if (text.length < 12) return false;
    final action = RegExp(r'(أنشئ|انشئ|ابن|طور|نفذ|صمم|اكتب|حلل|قارن|راجع|أصلح|اصلح|برمج|ابحث|build|create|develop|implement|design|analy[sz]e|compare|review|refactor|fix|research)').hasMatch(text);
    final scope = RegExp(r'(مشروع|تطبيق|موقع|برنامج|كود|ملف|نظام|قاعدة|واجهة|خدمة|project|application|website|software|code|file|system|service|api)').hasMatch(text);
    final sequence = RegExp(r'(ثم|بعد ذلك|خطوة|مراحل|متعدد|كامل|شامل|and then|after that|multiple steps|end.to.end)').hasMatch(text);
    return (action && (scope || text.length >= 55)) || sequence;
  }

  List<Map<String, dynamic>> createPlan(String request) {
    final text = request.trim().toLowerCase();
    if (text.isEmpty) throw ArgumentError.value(request, 'request');
    final software = RegExp(r'(كود|برمج|تطبيق|موقع|برنامج|ملف|نظام|قاعدة|واجهة|api|flutter|dart|python|javascript|software|code|app|website|project|refactor|debug|fix)').hasMatch(text);
    final research = RegExp(r'(ابحث|بحث|حلل|تحليل|قارن|دراسة|تقييم|مصادر|research|analy[sz]e|compare|evaluate|investigate)').hasMatch(text);
    final writing = RegExp(r'(اكتب|صياغة|مقال|تقرير|رسالة|محتوى|عرض|ترجم|write|draft|report|article|translate|proposal)').hasMatch(text);
    final actions = software
        ? <String>[
            'تحليل الهدف والمتطلبات والقيود ومعايير القبول.',
            'تصميم الحل وتقسيمه إلى مكونات وخطوات تنفيذ واضحة.',
            'تنفيذ المتطلبات باستخدام الأدوات المتاحة وتسجيل النتائج الفعلية.',
            'مراجعة المخرجات والتحقق مما اكتمل وما بقي دون ادعاء اختبارات لم تنفذ.',
          ]
        : research
            ? <String>[
                'تحديد أسئلة الدراسة ونطاقها ومعايير تقييم المعلومات.',
                'جمع وتنظيم المعلومات المتاحة وتحديد الفجوات.',
                'تحليل المعلومات ومقارنة النتائج وفق المعايير المحددة.',
                'مراجعة الاتساق وصياغة خلاصة تفصل الحقائق عن الاستنتاجات.',
              ]
            : writing
                ? <String>[
                    'تحديد هدف النص والجمهور والنبرة والمتطلبات.',
                    'إعداد المسودة الكاملة وفق البنية المناسبة.',
                    'مراجعة الدقة واللغة والترابط والالتزام بالمتطلبات.',
                    'إخراج النسخة النهائية وتوضيح المعلومات الناقصة أو الافتراضات.',
                  ]
                : <String>[
                    'تحليل المطلوب وتحديد النتيجة المستهدفة والقيود.',
                    'تنفيذ العمل على مراحل صغيرة قابلة للمراجعة.',
                    'مراجعة النتيجة والتحقق من اكتمال المطلوب.',
                  ];
    return List<Map<String, dynamic>>.generate(
      actions.length,
      (index) => <String, dynamic>{
        'step': index + 1,
        'action': actions[index],
        'status': 'pending',
      },
      growable: false,
    );
  }
}
