import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../application/gateway_settings.dart';

class AssistantConnectionScreen extends StatefulWidget {
  const AssistantConnectionScreen({super.key, required this.settings});
  final GatewaySettings settings;
  @override State<AssistantConnectionScreen> createState()=>_AssistantConnectionScreenState();
}
class _AssistantConnectionScreenState extends State<AssistantConnectionScreen> {
  final _url=TextEditingController(), _gatewayToken=TextEditingController(),
      _apiKey=TextEditingController(), _model=TextEditingController();
  String _provider='openrouter';
  bool _loading=true, _testing=false, _obscure=true;
  String? _status;
  List<String> _availableModels=[];
  static const _providers={'openrouter':'OpenRouter','gemini':'Google Gemini','openai':'OpenAI'};
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    _url.text=await widget.settings.baseUrl;
    _gatewayToken.text=await widget.settings.accessToken ?? '';
    _apiKey.text=await widget.settings.providerApiKey ?? '';
    _model.text=await widget.settings.model ?? 'openrouter/free';
    _provider=await widget.settings.provider;
    if(mounted)setState(()=>_loading=false);
  }
  Future<List<String>> _requestModels() async {
    final base=_url.text.trim().replaceFirst(RegExp(r'/+$'),'');
    final uri=Uri.tryParse(base);
    if(uri==null || uri.host.isEmpty || (uri.scheme!='https' && uri.host!='localhost' && uri.host!='10.0.2.2')) {
      throw const FormatException('تحقق من عنوان الخادم؛ يجب أن يستخدم HTTPS.');
    }
    if(_gatewayToken.text.trim().length<16)throw const FormatException('أدخل رمز الوصول للبوابة أولاً.');
    if(_apiKey.text.trim().length<8)throw const FormatException('أدخل مفتاح API الخاص بالمزود.');
    final client=HttpClient();
    try {
      final request=await client.getUrl(uri.resolve('/v1/models')).timeout(const Duration(seconds:25));
      request.headers
        ..set(HttpHeaders.authorizationHeader,'Bearer \${_gatewayToken.text.trim()}')
        ..set('x-ai-provider',_provider)
        ..set('x-provider-api-key',_apiKey.text.trim())
        ..set(HttpHeaders.acceptHeader,'application/json');
      final response=await request.close().timeout(const Duration(seconds:25));
      final body=await utf8.decoder.bind(response).join();
      if(response.statusCode<200 || response.statusCode>=300) {
        throw HttpException('فشل الاتصال (\${response.statusCode}): $body');
      }
      final decoded=jsonDecode(body) as Map<String,dynamic>;
      final data=decoded['data'];
      if(data is! List)throw const FormatException('استجابة قائمة النماذج غير صالحة.');
      return data.map((e)=>(e as Map<String,dynamic>)['id']?.toString()??'')
          .where((id)=>id.isNotEmpty).toSet().toList()..sort();
    } finally {client.close(force:true);}
  }
  Future<void> _test() async {
    setState(()=>_testing=true);
    try {
      final models=await _requestModels();
      if(!mounted)return;
      setState(() {
        _availableModels=models;
        _status=models.isEmpty?'تم الوصول للمزود، لكنه لم يُرجع قائمة نماذج.':'نجح الاتصال. تم العثور على \${models.length} نموذجاً.';
        if(_model.text.trim().isEmpty && models.isNotEmpty)_model.text=models.first;
      });
    } catch(e) {if(mounted)setState(()=>_status='تعذر الاتصال: $e');}
    finally {if(mounted)setState(()=>_testing=false);}
  }
  Future<void> _save() async {
    try {
      await _requestModels();
      await widget.settings.save(url:_url.text,token:_gatewayToken.text,provider:_provider,apiKey:_apiKey.text,model:_model.text);
      if(mounted)Navigator.of(context).pop(true);
    } catch(e) {if(mounted)setState(()=>_status='لم يتم الحفظ: $e');}
  }
  Future<void> _clear() async {
    await widget.settings.clear();
    if(!mounted)return;
    _url.clear();_gatewayToken.clear();_apiKey.clear();_model.clear();
    setState(()=>_status='تم حذف بيانات الاتصال المحفوظة من هذا الجهاز.');
  }
  @override void dispose(){_url.dispose();_gatewayToken.dispose();_apiKey.dispose();_model.dispose();super.dispose();}
  @override Widget build(BuildContext context) {
    if(_loading)return const Scaffold(body:Center(child:CircularProgressIndicator()));
    final theme=Theme.of(context);
    return Scaffold(appBar:AppBar(title:const Text('إعداد الذكاء الاصطناعي')),
      body:ListView(padding:const EdgeInsets.all(20),children:[
        Card(child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Icon(Icons.security,size:30),const SizedBox(height:8),
          Text('اتصال آمن بمزودك',style:theme.textTheme.titleLarge),const SizedBox(height:6),
          const Text('تُحفظ مفاتيح المزود في التخزين الآمن على جهازك، وتُرسل إلى بوابتك عبر HTTPS عند الطلب فقط. لا تُضمّن في APK ولا تُحفظ في ملفات الخادم.')
        ]))),
        const SizedBox(height:18),
        DropdownButtonFormField<String>(value:_provider,decoration:const InputDecoration(labelText:'مزود الذكاء الاصطناعي',border:OutlineInputBorder()),
          items:_providers.entries.map((e)=>DropdownMenuItem(value:e.key,child:Text(e.value))).toList(),
          onChanged:(v){if(v==null)return;setState((){
            _provider=v;_availableModels=[];
            _model.text=v=='openrouter'?'openrouter/free':v=='gemini'?'gemini-2.5-flash':'gpt-4.1-mini';_status=null;
          });}),
        const SizedBox(height:14),
        TextField(controller:_url,keyboardType:TextInputType.url,decoration:const InputDecoration(labelText:'رابط خادم Giant Agent',hintText:'https://your-gateway.run.app',border:OutlineInputBorder())),
        const SizedBox(height:14),
        TextField(controller:_gatewayToken,obscureText:true,decoration:const InputDecoration(labelText:'رمز الوصول للبوابة',helperText:'يُنشأ في إعدادات استضافة الخادم.',border:OutlineInputBorder())),
        const SizedBox(height:14),
        TextField(controller:_apiKey,obscureText:_obscure,decoration:InputDecoration(labelText:'مفتاح API للمزود',helperText:'مفتاح OpenRouter أو Gemini أو OpenAI.',border:const OutlineInputBorder(),
          suffixIcon:IconButton(onPressed:()=>setState(()=>_obscure=!_obscure),icon:Icon(_obscure?Icons.visibility:Icons.visibility_off)))),
        const SizedBox(height:14),
        TextField(controller:_model,decoration:const InputDecoration(labelText:'معرّف النموذج',hintText:'openrouter/free',border:OutlineInputBorder())),
        if(_availableModels.isNotEmpty)...[
          const SizedBox(height:8),
          DropdownButtonFormField<String>(value:_availableModels.contains(_model.text)?_model.text:null,
            decoration:const InputDecoration(labelText:'النماذج المكتشفة',border:OutlineInputBorder()),
            items:_availableModels.map((id)=>DropdownMenuItem(value:id,child:Text(id,overflow:TextOverflow.ellipsis))).toList(),
            onChanged:(v){if(v!=null)setState(()=>_model.text=v);}),
        ],
        const SizedBox(height:18),
        OutlinedButton.icon(onPressed:_testing?null:_test,
          icon:_testing?const SizedBox(width:18,height:18,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.wifi_tethering),
          label:Text(_testing?'جارٍ اختبار الاتصال…':'اختبار الاتصال وجلب النماذج')),
        if(_status!=null)Padding(padding:const EdgeInsets.symmetric(vertical:12),
          child:Text(_status!,style:TextStyle(color:_status!.startsWith('نجح')?Colors.green:theme.colorScheme.error))),
        const SizedBox(height:8),
        FilledButton.icon(onPressed:_testing?null:_save,icon:const Icon(Icons.save_outlined),label:const Text('اختبار الاتصال وحفظ الإعدادات')),
        TextButton.icon(onPressed:_clear,icon:const Icon(Icons.delete_outline),label:const Text('حذف بيانات الاتصال من الجهاز')),
      ]));
  }
}
