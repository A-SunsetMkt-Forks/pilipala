// ignore_for_file: avoid_print
import 'dart:developer';
import 'dart:io';
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:hive/hive.dart';
import 'package:pilipala/utils/storage.dart';
import 'package:pilipala/utils/utils.dart';
import 'package:pilipala/http/constants.dart';
import 'package:pilipala/http/interceptor.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

class Request {
  static final Request _instance = Request._internal();
  static late CookieManager cookieManager;
  static late final Dio dio;
  factory Request() => _instance;

  /// 设置cookie
  static setCookie() async {
    Box userInfoCache = GStrorage.userInfo;
    var cookiePath = await Utils.getCookiePath();
    var cookieJar = PersistCookieJar(
      ignoreExpires: true,
      storage: FileStorage(cookiePath),
    );
    cookieManager = CookieManager(cookieJar);
    dio.interceptors.add(cookieManager);
    var cookie = await cookieManager.cookieJar
        .loadForRequest(Uri.parse(HttpString.baseUrl));
    var userInfo = userInfoCache.get('userInfoCache');
    if (userInfo != null && userInfo.mid != null) {
      var cookie2 = await cookieManager.cookieJar
          .loadForRequest(Uri.parse(HttpString.tUrl));
      if (cookie2.isEmpty) {
        try {
          await Request().get(HttpString.tUrl);
        } catch (e) {
          log("setCookie, ${e.toString()}");
        }
      }
      setOptionsHeaders(userInfo);
    }

    if (cookie.isEmpty) {
      try {
        await Request().get(HttpString.baseUrl);
      } catch (e) {
        log("setCookie, ${e.toString()}");
      }
    }
    var cookieString =
        cookie.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
    dio.options.headers['cookie'] = cookieString;
  }

  // 从cookie中获取 csrf token
  static Future<String> getCsrf() async {
    var cookies = await cookieManager.cookieJar
        .loadForRequest(Uri.parse(HttpString.baseApiUrl));
    // for (var i in cookies) {
    //   print(i);
    // }
    String token = '';
    if (cookies.where((e) => e.name == 'bili_jct').isNotEmpty) {
      token = cookies.firstWhere((e) => e.name == 'bili_jct').value;
    }
    return token;
  }

  static setOptionsHeaders(userInfo) {
    dio.options.headers['x-bili-mid'] = userInfo.mid.toString();
    dio.options.headers['env'] = 'prod';
    dio.options.headers['app-key'] = 'android64';
    dio.options.headers['x-bili-aurora-eid'] = 'UlMFQVcABlAH';
    dio.options.headers['x-bili-aurora-zone'] = 'sh001';
    dio.options.headers['referer'] = 'https://www.bilibili.com/';
  }

  /*
   * config it and create
   */
  Request._internal() {
    //BaseOptions、Options、RequestOptions 都可以配置参数，优先级别依次递增，且可以根据优先级别覆盖参数
    BaseOptions options = BaseOptions(
      //请求基地址,可以包含子路径
      baseUrl: HttpString.baseApiUrl,
      //连接服务器超时时间，单位是毫秒.
      connectTimeout: const Duration(milliseconds: 12000),
      //响应流上前后两次接受到数据的间隔，单位为毫秒。
      receiveTimeout: const Duration(milliseconds: 12000),
      //Http请求头.
      headers: {
        'keep-alive': true,
        'user-agent': headerUa('pc'),
        'Accept-Encoding': 'gzip'
      },
      contentType: Headers.jsonContentType,
      persistentConnection: true,
    );

    dio = Dio(options);

    //添加拦截器
    dio.interceptors.add(ApiInterceptor());

    // 日志拦截器 输出请求、响应内容
    dio.interceptors.add(LogInterceptor(
      request: false,
      requestHeader: false,
      responseHeader: false,
    ));

    dio.transformer = BackgroundTransformer();
    dio.options.validateStatus = (status) {
      return status! >= 200 && status < 300 || status == 304 || status == 302;
    };
  }

  /*
   * get请求
   */
  get(url, {data, cacheOptions, options, cancelToken, extra}) async {
    Response response;
    Options options;
    String ua = 'pc';
    ResponseType resType = ResponseType.json;
    if (extra != null) {
      ua = extra!['ua'] ?? 'pc';
      resType = extra!['resType'] ?? ResponseType.json;
    }
    if (cacheOptions != null) {
      cacheOptions.headers = {'user-agent': headerUa(ua)};
      options = cacheOptions;
    } else {
      options = Options();
      options.headers = {'user-agent': headerUa(ua)};
      options.responseType = resType;
    }
    try {
      response = await dio.get(
        url,
        queryParameters: data,
        options: options,
        cancelToken: cancelToken,
      );
      return response;
    } on DioException catch (e) {
      print('get error: $e');
      return Future.error(await ApiInterceptor.dioError(e));
    }
  }

  /*
   * post请求
   */
  post(url, {data, queryParameters, options, cancelToken, extra}) async {
    // print('post-data: $data');
    Response response;
    try {
      response = await dio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: options,
        cancelToken: cancelToken,
      );
      // print('post success: ${response.data}');
      return response;
    } on DioException catch (e) {
      print('post error: $e');
      return Future.error(await ApiInterceptor.dioError(e));
    }
  }

  /*
   * 下载文件
   */
  downloadFile(urlPath, savePath) async {
    Response response;
    try {
      response = await dio.download(urlPath, savePath,
          onReceiveProgress: (int count, int total) {
        //进度
        // print("$count $total");
      });
      print('downloadFile success: ${response.data}');

      return response.data;
    } on DioException catch (e) {
      print('downloadFile error: $e');
      return Future.error(ApiInterceptor.dioError(e));
    }
  }

  /*
   * 取消请求
   *
   * 同一个cancel token 可以用于多个请求，当一个cancel token取消时，所有使用该cancel token的请求都会被取消。
   * 所以参数可选
   */
  void cancelRequests(CancelToken token) {
    token.cancel("cancelled");
  }

  String headerUa(ua) {
    String headerUa = '';
    if (ua == 'mob') {
      headerUa = Platform.isIOS
          ? 'Mozilla/5.0 (iPhone; CPU iPhone OS 10_3_1 like Mac OS X) AppleWebKit/603.1.30 (KHTML, like Gecko) Version/10.0 Mobile/14E304 Safari/602.1'
          : 'Mozilla/5.0 (Linux; Android 11; Pixel 5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/90.0.4430.91 Mobile Safari/537.36';
    } else {
      headerUa =
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 13_3_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.4 Safari/605.1.15';
    }
    return headerUa;
  }
}
