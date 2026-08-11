import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/shared/utils/question_number_detector.dart';

void main() {
  const detector = QuestionNumberDetector.instance;

  group('阿拉伯数字 + 分隔符', () {
    test('1.', () => expect(detector.extractNumber('1. 计算 3+5='), '1'));
    test('1、', () => expect(detector.extractNumber('1、求 x'), '1'));
    test('1）', () => expect(detector.extractNumber('1）求 x'), '1'));
    test('1)', () => expect(detector.extractNumber('1)求 x'), '1'));
    test('（1）', () => expect(detector.extractNumber('（1）计算'), '1'));
    test('(1)', () => expect(detector.extractNumber('(1)计算'), '1'));
    test('1:：', () => expect(detector.extractNumber('1:：题目'), '1'));
    test('1．', () => expect(detector.extractNumber('1．题目'), '1'));
    test('12.', () => expect(detector.extractNumber('12. 题目'), '12'));
    test('1: ', () => expect(detector.extractNumber('1: 题目'), '1'));
  });

  group('"第"前缀', () {
    test('第1题', () => expect(detector.extractNumber('第1题 计算'), '1'));
    test('第 2 题', () => expect(detector.extractNumber('第 2 题内容'), '2'));
    test('第三题', () => expect(detector.extractNumber('第三题内容'), '3'));
    test('第1章', () => expect(detector.extractNumber('第1章：函数'), '1'));
    test('第10题', () => expect(detector.extractNumber('第10题内容'), '10'));
  });

  group('"题"前缀', () {
    test('题1', () => expect(detector.extractNumber('题1：内容'), '1'));
    test('题 2', () => expect(detector.extractNumber('题 2：内容'), '2'));
  });

  group('英文前缀', () {
    test('Q1', () => expect(detector.extractNumber('Q1: What'), '1'));
    test('Question 1', () => expect(detector.extractNumber('Question 1: What'), '1'));
    test('q1', () => expect(detector.extractNumber('q1: what'), '1'));
    test('question 1', () => expect(detector.extractNumber('question 1 what'), '1'));
  });

  group('中文数字', () {
    test('一、', () => expect(detector.extractNumber('一、内容'), '1'));
    test('二、', () => expect(detector.extractNumber('二、内容'), '2'));
    test('十、', () => expect(detector.extractNumber('十、内容'), '10'));
    test('二十、', () => expect(detector.extractNumber('二十、内容'), '20'));
    test('三十、', () => expect(detector.extractNumber('三十、内容'), '30'));
    test('一.', () => expect(detector.extractNumber('一.内容'), '1'));
    test('二．', () => expect(detector.extractNumber('二．内容'), '2'));
  });

  group('罗马数字', () {
    test('I.', () => expect(detector.extractNumber('I. content'), '1'));
    test('II.', () => expect(detector.extractNumber('II. content'), '2'));
    test('IV.', () => expect(detector.extractNumber('IV. content'), '4'));
    test('X.', () => expect(detector.extractNumber('X. content'), '10'));
    test('III.', () => expect(detector.extractNumber('III. content'), '3'));
    test('IX.', () => expect(detector.extractNumber('IX. content'), '9'));
  });

  group('非题号', () {
    test('苹果', () => expect(detector.extractNumber('苹果'), isNull));
    test('今天天气', () => expect(detector.extractNumber('今天天气真好'), isNull));
    test('hello', () => expect(detector.extractNumber('hello world'), isNull));
    test('空字符串', () => expect(detector.extractNumber(''), isNull));
  });

  group('边界', () {
    test('1 单独（无分隔符）应返回 null', () {
      expect(detector.extractNumber('1'), isNull);
    });
    test('第 单独（无数字）应返回 null', () {
      expect(detector.extractNumber('第'), isNull);
    });
    test('题 单独（无数字）应返回 null', () {
      expect(detector.extractNumber('题'), isNull);
    });
    test('Q 单独（无数字）应返回 null', () {
      expect(detector.extractNumber('Q'), isNull);
    });
  });

  group('hasQuestionNumber', () {
    test('1. 返回 true', () => expect(detector.hasQuestionNumber('1. 题目'), isTrue));
    test('（1）返回 true', () => expect(detector.hasQuestionNumber('（1）题目'), isTrue));
    test('第一题 返回 true', () => expect(detector.hasQuestionNumber('第一题'), isTrue));
    test('一、 返回 true', () => expect(detector.hasQuestionNumber('一、内容'), isTrue));
    test('I. 返回 true', () => expect(detector.hasQuestionNumber('I. content'), isTrue));
    test('苹果 返回 false', () => expect(detector.hasQuestionNumber('苹果'), isFalse));
    test('1 单独 返回 false', () => expect(detector.hasQuestionNumber('1'), isFalse));
    test('空字符串 返回 false', () => expect(detector.hasQuestionNumber(''), isFalse));
  });
}
