//
//  ViewController.swift
//  Bezier
//
//  Created by Chingiz Bayshruin on 28.06.17.
//  Copyright © 2017 Chingiz Bayshruin. All rights reserved.
//

import UIKit
import Darwin


/**
 *     Построение плавного графика на основе массива [Float] значений, получаемых извне в JSON-формате
 *
 *       1) График строится на основе ANDLineChartView  https://github.com/anaglik/ANDLineChartView (Objective C проект) и
 *            https://github.com/johnyorke/JYGraphView
 *       2) Были сделаны изменения в логике просчета кубических кривых Безье, дабы они не выходили за границы точек, если данная точка
 *           самая высокая или низкая по сравнению со своими соседями слева и справа (стандартный алгоритм
 *              https://medium.com/@ramshandilya/draw-smooth-curves-through-a-set-of-points-in-ios-34f6d73c8f9   этим как раз-таки и грешил
 *          Как это можно было сделать помогла вот эта тема - https://stackoverflow.com/questions/13719143/draw-graph-curves-with-uibezierpath
 *          Что в итоге получилось, смотрте в CubicCurvePath.swift
 *       3) График можно встроить в проект обычным включением 4 файлов, содержащихся в папке ANDLineChart, никаких pod'ов не требуется
 *       4) График можно включить в ViewController 2 способами - прямым добавлением на superview или на UIView-подлжоку (вариант 2)
 *           И в том и в другом случае необходимо задание 2 constraints - они в данном файле уже прописаны
 *       5) Внешний вид графика задается ANDLineChartViewDataSource и ANDLineChartViewDelegate функциями
 *       6) Также, показывать или нет ось ординат (Y-ось) и отметки там задается в ANDLineChartView в функции setupDefaultAppearence()
 *       7) Отментки на оси абсцисс (X-ось) и покрытие или нет его градиентной заливкой задается в ANDLineInternalLineChartView.swift
 *         в функции layoutSubviews()  и в setupLabels()
 *       8) Название графика задается в ANDLineChartView.swift в функции setupGraphTitle()
 *       9) Внимательный читатель может заметить использование переменной EXTRA_TO_MAX_NUMBER. Она нужна для того, чтобы было место для вехней надписи графика и
 *           нижний отметок на оси X
 *       10) На случай работы с серверами, работающими по протоколу http в файл Info.plist включено соответствующее разрещающее правило
 *               <key>NSAppTransportSecurity</key>
 *               <dict>
 *                     <key>NSAllowsArbitraryLoads</key>
 *                      <true/>
 *               </dict>
 *          А то можно нарваться на ошибку Error Domain=NSURLErrorDomain Code=-1022 
 *           "The resource could not be loaded because the App Transport Security policy requires the use of a secure connection."
 *
 *       11) ВНИМАНИЕ, парсинг JSON настроен на вот такой формат:  [{"date":"506948248.665283","value":"-23.9"},{"date":"507034648.665283","value":"40.3"}...]
 *          Таймстемп можно передавать и без микросекунд, то есть просто "date":"506948248" ибо сейчас программа все равно регулярынм выражением берет
 *          только первый блок цифр
 *       12) URL адрес откуда тянется JSON задается в константе urlJson
 *
 */


// Наша модель данных
struct DataSet {
    var timestamp: Int
    var value : Float
    var date : String?
    
    init (timestamp: Int, value: Float) {
        self.timestamp  = timestamp
        self.value = value
    }
}



class ViewController: UIViewController {
    
    
    @IBOutlet weak var viewForChart: UIView!
    @IBOutlet weak var activityIndicator: UIActivityIndicatorView!
    @IBOutlet weak var whiteView: UIView!
    
    
    // загружаем тестовый JSON отсюда
    let urlJson = "http://xn----9sbb2ac5bgif6fd.xn--p1ai/test_bezier_data.json"
    // Наш массив с данными (распарсенными из сетевого JSON'а)
    var dataSets : [DataSet] = []
    // Наше регулярное выражение по выцеплению именно таймстемпа
    let patternForTimeStamp = "^[\\d]*"
    
    
    var MAX_NUMBER_COUNT     = Int()
    var MAX_NUMBER           = Float()
    var MIN_NUMBER           = Float()
    var EXTRA_TO_MAX_NUMBER  = Float()
    var _elements : [Int]    = [Int]()
    var _chartView : ANDLineChartView?
    var _maxValue            = Float()
    var _numbersCount : Int  = Int()
    
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        viewForChart.backgroundColor = UIColor.clear
        _chartView = ANDLineChartView(frame: CGRect.zero)
        
        // сначала мы получаем данные, а потом под них настраиваем наш график
        getData()
    }
    
    @IBAction func reloadData(_ sender: Any) {
        getData()
    }
    
    
    func getData() {
        
        // удаляем старый график и показываем activity indicator
        whiteView.alpha = 1.0
        whiteView.isHidden = false
        activityIndicator.isHidden = false
        activityIndicator.startAnimating()
        whiteView.backgroundColor = UIColor.white
        _chartView?.removeFromSuperview()
        self.view.layoutIfNeeded()
        
        // обнуляем данные
        self.dataSets = []
        
        
        // обнуляю режим кэша
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        let session = URLSession.init(configuration: config)
        
        
        let jsonUrl = NSURL(string: urlJson)!
        let jsonUrlRequest = NSMutableURLRequest(url: jsonUrl as URL)
        jsonUrlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        
        
        //URLSession.shared.dataTask(with: jsonUrlRequest as URLRequest) { (data, response, error) -> Void in
        session.dataTask(with: jsonUrlRequest as URLRequest, completionHandler:  { (data, response, error) -> Void in
            guard let data = data else {
                print("Ошибка в ответе сервера \(error)")
                return
            }
            
            // пробуем распарсить JSON
            do {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: String]] {
                    // проходимся циклом
                    for i in 0..<jsonArray.count{
                        if let jsonDict = jsonArray[i] as? [String : String] {
                            
                            let timeStampString = matches(for: self.patternForTimeStamp, in: jsonDict["date"]!)
                            let timeStamp = Int(timeStampString[0]) ?? 0
                            let value = Float(jsonDict["value"]!) ?? 0.0
                            self.dataSets.append( DataSet(timestamp: timeStamp, value: value ) )
                        }
                    }
                    // Запускаем отрисовку графика в MainThread'е
                    DispatchQueue.main.async {
                        self.getDatesAndDrawGraph()
                    }
                    
                }
            } catch let parseError {
                print("Ошибка парсинга: \(parseError)")
                let responseString = String(data: data, encoding: .utf8)
                print("raw response: \(responseString)")
            }
        }).resume()
        
    }// --- end of func getData() ---------------
    
    
    // РИСУЕМ ГРАФИК
    func getDatesAndDrawGraph() {
        
        // сначала переводим таймстемпы в обычные даты
        for i in 0..<self.dataSets.count {
            let date = NSDate(timeIntervalSince1970: TimeInterval(self.dataSets[i].timestamp) )
            let dayTimePeriodFormatter = DateFormatter()
            dayTimePeriodFormatter.dateFormat = "d MMMM, hh:mm"
            let dateString = dayTimePeriodFormatter.string(from: date as Date)
            self.dataSets[i].date = dateString
        }
        
        // определяем самое максимальное значение
        var max : Float = FLT_MIN
        for i in 0..<self.dataSets.count {
            if max < self.dataSets[i].value {
                max = self.dataSets[i].value
                
            }
        }
        
        // определяем самое минимальное значение
        var min : Float = FLT_MAX
        for i in 0..<self.dataSets.count {
            if min > self.dataSets[i].value {
                min = self.dataSets[i].value
            }
        }
        
        // настраиваем сам график ANDLineChartView
        MAX_NUMBER_COUNT = self.dataSets.count
        MAX_NUMBER = max
        MIN_NUMBER = min
        
        EXTRA_TO_MAX_NUMBER = abs( MIN_NUMBER -  MAX_NUMBER ) * 0.15
        
        
        _maxValue     = self.MAX_NUMBER
        _numbersCount = self.MAX_NUMBER_COUNT;
        _chartView = ANDLineChartView(frame: CGRect.zero)
        _chartView?.translatesAutoresizingMaskIntoConstraints = false
        _chartView?.dataSource        = self
        _chartView?.delegate          = self
        _chartView?.animationDuration = 0.4
        
        // ВАРИАНТ 1 - chartView добавляется прямо на superview - self.view
        // self.view.addSubview(_chartView!)
        // self.setupConstraints()
        
        // ВАРИАНТ 2 - chartView добавляется на view-подложку
        self.viewForChart.addSubview(_chartView!)
        self.setupConstraints()
        
        
        //убираем view-заглушку и активити индикатор
        whiteView.isHidden = true
        activityIndicator.isHidden = true
        activityIndicator.stopAnimating()
        
        // анимированное появление
        //        UIView.animate(withDuration: 1.7, delay: 0.1, options: .curveEaseIn, animations: {
        //            self.whiteView.alpha = 0.0
        //            self.view.layoutIfNeeded()
        //        }) { _ in
        //            self.whiteView.isHidden = true
        //        }
        self.whiteView.alpha = 0.0
        self.whiteView.isHidden = true
        
    }
    
    
    // у нас данные тянуться уже с сети, потому не нужна эта заглушка
    func arrayWithRandomNumbers() -> [Int] {
        var random = [Int]()
        for i in 0..<_numbersCount {
            var r : UInt = UInt(arc4random_uniform( UInt32(_maxValue + 1)   )   )
            random.append(Int(r))
        }
        return random
    }
    
    
    
    // У нас 2 варианта размещения ANDLineChartView - метод прямого добавления на superview и метод
    // добавления на UIView-подложку. Соответственно, два варианта выставления constraint'ов
    func setupConstraints() {
        
        // ВАРИАНТ 1 - chartView добавляется прямо на superview - self.view
        /*let topLayoutGuide =  self.topLayoutGuide
         let views: [String: AnyObject] = ["_chartView"    : _chartView!,
         "topLayoutGuide": topLayoutGuide]*/
        //let constraints1 = NSLayoutConstraint.constraints(withVisualFormat: "V:[topLayoutGuide]-20-[_chartView]-20-|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: views)
        //let constraints2 = NSLayoutConstraint.constraints(withVisualFormat: "H:|[_chartView]|", options: NSLayoutFormatOptions(rawValue: 0), metrics: nil, views: views)
        // self.view.addConstraints(constraints1)
        // self.view.addConstraints(constraints2)
        
        
        // ВАРИАНТ 2 - chartView добавляется на view-подложку
        let views: [String: AnyObject] = [ "viewForChart"  : viewForChart,
                                           "_chartView"    : _chartView! ]
        let constraints1 = NSLayoutConstraint.constraints(withVisualFormat: "V:|-(-10)-[_chartView]-(-10)-|", options: NSLayoutFormatOptions.alignAllCenterY, metrics: nil, views: views)
        let constraints2 = NSLayoutConstraint.constraints(withVisualFormat: "H:|-(-10)-[_chartView]-(-10)-|", options: NSLayoutFormatOptions.alignAllCenterX, metrics: nil, views: views)
        self.viewForChart.addConstraints(constraints1)
        self.viewForChart.addConstraints(constraints2)
        
    }
}//----- end of class declaration -----------------






// служебная функция для вычленения таймстемпа из сервергого таймстемпа формата "507034648.665283"
// нам нужна только та часть, что до точки - ее мы и выцепляем (см. let patternForTimeStamp = "^[\\d]*" )
func matches(for regex: String, in text: String) -> [String] {
    do {
        let regex = try NSRegularExpression(pattern: regex)
        let nsString = text as NSString
        let results = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return results.map { nsString.substring(with: $0.range)}
    } catch let error {
        print("invalid regex: \(error.localizedDescription)")
        return []
    }
}







// MARK:   Методы  ANDLineChartViewDataSource протокола ----------------------------
extension ViewController : ANDLineChartViewDataSource {
    
    // Передача отформатированной в String даты для надписей на оси X
    func chartView(_ chartView: ANDLineChartView, dateForElementAtRow row: Int) -> String? {
        return self.dataSets[row].date ?? "нет данных"
    }
    
    // Передача значений для каждого столбца (row)
    func chartView(_ chartView: ANDLineChartView, valueForElementAtRow row: Int) -> CGFloat? {
        return CGFloat( self.dataSets[row].value )
    }
    
    // Передача количества столбцов в графике
    func numberOfElements(in chartView: ANDLineChartView) -> Int? {
        return MAX_NUMBER_COUNT
    }
    
    // Установка количество насечек на оси Y
    func numberOfGridIntervals(in chartView: ANDLineChartView) -> Int? {
        return Int(12.0)
    }
    
    // Передача подписей к Y-оси
    func chartView(_ chartView: ANDLineChartView, descriptionForGridIntervalValue interval: CGFloat) -> String {
        return  String.init(format: "%.1f", interval)
    }
    
    // Определение верхней границы в оси Y - по сути через эту функцию мы определяем высоту графика
    // Добавляем еще сверху, чтобы верхние надписи к значениемям были видны
    func maxValueForGridInterval(in chartView: ANDLineChartView) -> CGFloat? {
        return CGFloat(self.MAX_NUMBER) + CGFloat(self.EXTRA_TO_MAX_NUMBER)*2.0
    }
    
    // Определение нижней границы в оси Y - также как и предыдущая функция по сути регулирует высоту графика
    // Мы также снизу добавляем еще пространства, чтобы  были видны подпсии к стобцам (даты)
    func minValueForGridInterval(in chartView: ANDLineChartView) -> CGFloat? {
        return  CGFloat(MIN_NUMBER) - CGFloat(self.EXTRA_TO_MAX_NUMBER)*3.1
    }
}//--------------------------------------------------------------------------------------


// MARK:   Методы o ANDLineChartViewDelegate протокола ----------------------------
extension ViewController : ANDLineChartViewDelegate {
    
    // Установка расстояния между столбцами
    func chartView(_ chartView: ANDLineChartView, spacingForElementAtRow row: Int) -> CGFloat {
        return (row == 0) ? 25.0 : 30.0
    }
}



